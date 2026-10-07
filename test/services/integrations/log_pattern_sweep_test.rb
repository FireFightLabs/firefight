require "test_helper"

class Integrations::LogPatternSweepTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SWEEP = Integrations::LogPatternSweep

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = @northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    @logs = @northflank.tools.create!(name: "search_logs", description: "Logs", read_only: true, enabled: true, params_schema: { "type" => "object" })
    @web = resource!("web")
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: @web)
  end

  test "the plan queues one read per connection for the resources in scope that a connection reads logs for" do
    resource!("unlinked")

    assert_enqueued_with(job: Integrations::LogPatternReadJob, args: [ @row, [ @web.id ] ]) { SWEEP.plan!(@workspace) }
  end

  test "a connection reads at most its daily cap of resources" do
    api = resource!("api")
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: api)
    SWEEP.stubs(:per_connection).returns(1)

    assert_enqueued_jobs(1, only: Integrations::LogPatternReadJob) { SWEEP.plan!(@workspace) }
    assert_equal 1, enqueued_jobs.find { |job| job["job_class"] == "Integrations::LogPatternReadJob" }["arguments"].last.size
  end

  test "with logs switched off nothing is read, and nothing is queued" do
    @logs.update!(enabled: false)
    Integrations::NativeExecutor.expects(:call).never

    assert_no_enqueued_jobs(only: Integrations::LogPatternReadJob) { SWEEP.plan!(@workspace) }
  end

  test "a read samples several windows across the week through the logs capability, as the map sweep, and keeps the patterns" do
    now = Time.zone.parse("2026-10-06T12:00:00Z")
    asked = []
    Integrations::NativeExecutor.expects(:call).times(SWEEP::WINDOWS).with do |tool:, arguments:, **|
      asked << arguments
      tool == @logs
    end.returns(logs_answer([ "user ada logged in", "user bob logged in", "ERROR db timeout after 30 ms" ]))

    SWEEP.read!(@row, [ @web.id ], now: now)

    assert_equal(asked.map { |arguments| arguments.values_at("resource", "limit") }.uniq, [ [ "web", SWEEP::LINES ] ])
    ends = asked.map { |arguments| Time.zone.parse(arguments["end"]) }
    assert_equal ends.uniq.size, SWEEP::WINDOWS
    assert(ends.all? { |ended| ended.between?(now - 7.days, now) })
    assert_equal ends.map(&:hour).uniq.size, SWEEP::WINDOWS, "each window falls at another hour"
    assert_equal [ "web-<NUM> user <*> logged in", "web-<NUM> ERROR db timeout after <NUM> ms" ], @web.log_templates.most_lines_first.map(&:template)
    ledgered = Ability::Invocation.where(workspace: @workspace, action_key: "northflank.search_logs")
    assert_equal [ [ AbilityGateway::SOURCE_MAP_SWEEP, SystemAgent.map_sweep.id ] ], ledgered.pluck(:source, :principal_id).uniq
    assert_nil @row.reload.log_patterns_error
  end

  test "a rate limit stops the connection's read and says so, and a provider's refusal keeps the patterns from before" do
    ResourceMap::LogTemplate.record!(@row, @web, ResourceMap::LogMiner.mine([ "worker started" ]))
    Integrations::NativeExecutor.expects(:call).once.raises(Integrations::NorthflankApi::RateLimited.new("Northflank answered 429: slow down"))

    SWEEP.read!(@row, [ @web.id ])

    assert_match "Northflank answered 429", @row.reload.log_patterns_error
    assert_equal [ "worker started" ], @web.log_templates.map(&:template)
  end

  test "the daily job queues a plan per workspace with a map" do
    assert_enqueued_with(job: Integrations::LogPatternSweepJob, args: [ @workspace.id ]) { Integrations::LogPatternSweepJob.perform_now }
  end

  private

  def resource!(id)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: id, name: id,
                                  integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def logs_answer(lines)
    log_lines = lines.map { |text| Integrations::Telemetry::LogLine.new(at: Time.current, source: "web-1", text: text) }
    Integrations::Telemetry.result(Integrations::Telemetry.logs_text(log_lines, asked: "web"), link: nil)
  end
end
