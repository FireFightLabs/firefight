require "test_helper"

module Integrations
  class BaselineSweepTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @workspace = workspaces(:slack_workspace_one)
      @integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
      @row = @integration.integration_environments.create!
      ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [
        ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web")
      ]))
      @web = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web")
    end

    test "a day's read asks the connection for its resources over the last week and keeps what normal looks like" do
      now = Time.zone.parse("2026-09-30T05:00:00Z")
      Packs::Northflank.any_instance.expects(:baselines_of).with { |row, resources, window| row == @row && resources == [ @web ] && window == ((now - 7.days)..now) }
                       .returns([ ResourceMap::Baseline::Found.new(key: @web.key, metric: "cpu", label: "CPU", unit: "vCPU", points: [ [ now, 0.2 ] ]) ])

      @row.update!(baseline_error: "Northflank answered 503")

      assert_equal 1, BaselineSweep.run!(@row, now: now)
      assert_equal "CPU", @web.baselines.sole.label
      assert_nil @row.reload.baseline_error
    end

    test "a connection that cannot be read keeps yesterday's baselines and says why, and one that reads no metrics does nothing" do
      Packs::Northflank.any_instance.stubs(:baselines_of).raises(Integrations::Error, "Northflank answered 503")
      assert_equal 0, BaselineSweep.run!(@row)
      assert_equal "Northflank answered 503", @row.reload.baseline_error

      Packs::Northflank.any_instance.stubs(:baselines_of).returns(nil)
      assert_equal 0, BaselineSweep.run!(@row)
      assert_nil @row.reload.baseline_error, "a connection with nothing to read is not failing, so the earlier error goes"

      ResourceMap::Resource.where(integration_environment: @row).update_all(removed_at: Time.current)
      @row.update!(baseline_error: "Northflank answered 503")
      Packs::Northflank.any_instance.expects(:baselines_of).never
      assert_equal 0, BaselineSweep.run!(@row)
      assert_nil @row.reload.baseline_error, "a connection with nothing on the map is not failing either"
    end

    test "the daily job queues one read per connection" do
      assert_enqueued_with(job: BaselineSweepJob, args: [ @row ]) { BaselineSweepJob.perform_now }
    end

    test "an observability tool reads normal for what it watches, named for itself, and never removes what the platform read" do
      now = Time.zone.parse("2026-09-30T05:00:00Z")
      datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", settings: { "server_url" => "https://mcp.datadoghq.com/v1/mcp" })
      watching = datadog.integration_environments.create!
      datadog.tools.create!(name: "get_datadog_metric", read_only: true, enabled: true)
      ResourceMap::Baseline.record!(@row, [ @web ], [ found(@web, "cpu", "CPU", now, 0.2) ], window_from: now - 7.days, window_to: now)
      McpExecutor.expects(:baselines_of).with { |row, resources, _window| row == watching && resources == [ @web ] }.returns([ found(@web, "cpu", "CPU", now, 0.4) ])

      assert_equal 1, BaselineSweep.run!(watching, now: now)

      assert_equal [ [ "CPU", 0.2, @row.id ], [ "CPU (Datadog)", 0.4, watching.id ] ],
                   @web.baselines.order(:label).map { |baseline| [ baseline.label, baseline.typical, baseline.integration_environment_id ] }
    end

    test "an observability tool wired to an environment watches only what is held in it" do
      @row.update!(catalog_entry_id: catalog_entries(:production_env).id)
      datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", settings: { "server_url" => "https://mcp.datadoghq.com/v1/mcp" })

      assert_equal [ @web ], Capabilities.watched(datadog.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id), Capabilities::METRICS)
      assert_empty Capabilities.watched(datadog.integration_environments.create!(catalog_entry_id: catalog_entries(:development_env).id), Capabilities::METRICS)
      assert_empty Capabilities.watched(@row, Capabilities::METRICS), "a platform watches nothing"
    end

    private

    def found(resource, metric, label, at, value) = ResourceMap::Baseline::Found.new(key: resource.key, metric: metric, label: label, unit: "%", points: [ [ at, value ] ])
  end
end
