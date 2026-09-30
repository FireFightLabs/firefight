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
    end

    test "the daily job queues one read per connection" do
      assert_enqueued_with(job: BaselineSweepJob, args: [ @row ]) { BaselineSweepJob.perform_now }
    end
  end
end
