require "test_helper"

# A person's production release runs a Northflank workflow. Halon watches its newest run through run history, which
# follows it to the end, names the step that failed with why from that step's own log, and is woken by a release
# flow's live update rather than waiting for its next minute. Only Northflank's API is stubbed: the pack, the gateway,
# the capability routing and the watch all run as they do in production.
class Conversation::ReleaseWatchTest < ActiveSupport::TestCase
  include SlackClientStubHelper
  include ActiveJob::TestHelper

  NorthflankApi = Integrations::NorthflankApi
  Pack = Integrations::Packs::Northflank

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @turn = Conversation::Turn.new(@conversation, asker: @alice)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = integration.integration_environments.create!
    Pack.store_credentials!(@row, Pack::API_TOKEN => "nf-token")
    @row.store_fields!(Pack::PROJECT => "firefight")
    Integrations::DiscoveryService.sync!(integration)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "firefight-labs/firefight", kind: ResourceMap::KIND_WORKFLOW,
                                  external_id: "release", name: "Release", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
    NorthflankApi.any_instance.stubs(:workflows).returns(Integrations::Pages::Read.new(items: [ { "id" => "release", "name" => "Release" } ], complete: true))
    NorthflankApi.any_instance.stubs(:services).returns(Integrations::Pages::Read.new(items: [], complete: true))
    NorthflankApi.any_instance.stubs(:addons).returns(Integrations::Pages::Read.new(items: [], complete: true))
    NorthflankApi.any_instance.stubs(:jobs).returns(Integrations::Pages::Read.new(items: [ { "id" => "migrate", "name" => "migrate", "jobType" => "manual" } ], complete: true))
    stub_post_message
    @started = 30.seconds.ago.change(usec: 0)
  end

  test "a watch on the release workflow's newest run follows it through run history to success" do
    runs(history)
    said = Conversation::Watches.start(@turn, watch)
    watch = @conversation.chat.watches.sole

    assert_match "This usually takes about 18 minutes", said
    assert_equal @row.id, watch.steps.sole.integration_environment_id, "it reads through the connection, so that connection's live updates wake it"

    runs([ listed("r10", "running", @started) ] + history)
    run_details("r10", "running", build: "running")
    check!(watch)
    step = watch.steps.sole.reload
    assert_equal [ "r10", Chat::Watch::Step::STATUS_RUNNING ], [ step.followed_run_id, step.status ]
    assert_match "Build builder running", step.summary

    runs([ listed("r10", "success", @started, concluded: @started + 12.minutes) ] + history)
    run_details("r10", "success", build: "success", migrate: "success", concluded: @started + 12.minutes)
    travel(13.minutes) { check!(watch) }

    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
    assert_includes watch.updates.map(&:text), "Production release succeeded after 12 minutes."
  end

  test "a failed step is named with why from its own log, and the watch ends failed" do
    runs(history)
    Conversation::Watches.start(@turn, watch)
    watch = @conversation.chat.watches.sole
    Investigation.stubs(:unavailable_reason).returns("Halon is off for this test")
    NorthflankApi.any_instance.expects(:logs).with("firefight", "jobs", "migrate", has_entries("runId" => "run-77")).at_least_once
                 .returns([ { "ts" => @started.iso8601, "log" => "ERROR: relation \"users\" already exists" } ])

    runs([ listed("r10", "failure", @started, concluded: @started + 4.minutes) ] + history)
    run_details("r10", "failure", build: "success", migrate: "failure", concluded: @started + 4.minutes)
    travel(5.minutes) { check!(watch) }

    failed = watch.updates.find_by!(kind: Chat::Watch::Update::KIND_PART_FAILED)
    assert_match "Production release: Run job migrate failed Migration exited with code 1", failed.text
    assert_match "relation \"users\" already exists", failed.text
    assert_equal Chat::Watch::STATUS_FAILED, watch.reload.status
    assert Ability::Invocation.where(workspace: @workspace, action_key: "northflank.search_logs").exists?
  end

  test "a release flow's live update wakes the watch now rather than at its next minute" do
    runs(history)
    Conversation::Watches.start(@turn, watch)
    watch = @conversation.chat.watches.sole
    clear_enqueued_jobs
    payload = { "event" => "release-flow-template-run:update", "data" => { "pipeline" => { "id" => "shop" }, "stage" => "Production" } }
    events = Integrations::MapEventSources::Northflank.events(payload, headers: { "x-northflank-notification-integration-event-id" => "evt-9" })

    assert_enqueued_with(job: WatchCheckJob, args: [ watch.id ]) { Integrations::MapEvents.receive!(@row, events) }
  end

  private

  def watch
    { "title" => "the production release", "steps" => [ { "label" => "Production release", "capability" => "run_history", "resource" => "Release", "name" => "Release" } ] }
  end

  def history
    [ 5, 4, 3 ].map { |days| listed("r#{days}", "success", days.days.ago, concluded: days.days.ago + 18.minutes) }
  end

  def listed(id, status, started, concluded: nil)
    { "id" => id, "status" => status, "concluded" => concluded.present?, "startedAt" => started.utc.iso8601, "concludedAt" => concluded&.utc&.iso8601 }.compact
  end

  def runs(listed) = NorthflankApi.any_instance.stubs(:workflow_runs).returns(listed)

  def run_details(id, status, build:, migrate: nil, concluded: nil)
    start = @started.to_i
    migration = { "kind" => "JobRun", "ref" => "migrate", "spec" => { "jobId" => "migrate" } }
    if migrate
      migration["response"] = { "status" => migrate, "startTime" => start + 60, "endTime" => start + 200, "data" => { "id" => "run-77" } }
      migration["response"]["error"] = { "code" => 1, "message" => "Migration exited with code 1" } if migrate == "failure"
    end
    NorthflankApi.any_instance.stubs(:workflow_run).with("firefight", "release", id).returns(
      "id" => id, "status" => status, "concluded" => concluded.present?, "startedAt" => @started.utc.iso8601, "concludedAt" => concluded&.utc&.iso8601,
      "spec" => { "kind" => "Workflow", "spec" => { "type" => "sequential", "steps" => [
        { "kind" => "Build", "ref" => "build", "spec" => { "id" => "builder", "type" => "service" },
          "response" => { "status" => build, "startTime" => start, "data" => { "id" => "brave-otter-12" } } },
        migration
      ] } }
    )
  end

  def check!(watch)
    Chat::Watch.where(id: watch.id).update_all(check_claimed_at: nil, checked_at: nil)
    Conversation::Watches.check!(watch.reload)
  end
end
