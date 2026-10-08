require "test_helper"

# What a stopped worker leaves part way is run again or ended with a plain reason, once, by the sweep.
class RecoverySweepJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )
  end

  test "it runs again every job the queue failed when its worker stopped" do
    InterruptedJob.expects(:run_again!).once.returns(0)

    RecoverySweepJob.perform_now
  end

  test "a run whose worker died is handed to a new one" do
    @investigation.claim!

    travel Investigation::LEASE + 1.minute do
      assert_enqueued_with(job: InvestigationJob, args: [ @investigation.id ]) { RecoverySweepJob.perform_now }
    end
  end

  test "a run a worker still holds is left alone" do
    @investigation.claim!

    assert_no_enqueued_jobs(only: InvestigationJob) { RecoverySweepJob.perform_now }
  end

  test "a run that is over is left alone" do
    @investigation.claim!
    @investigation.finish!(status: Investigation::STATUS_FAILED, error_summary: "RuntimeError")

    travel Investigation::LEASE + 1.minute do
      assert_no_enqueued_jobs(only: InvestigationJob) { RecoverySweepJob.perform_now }
    end
  end

  test "a postmortem draft whose job was lost ends failed, saying why, and its author is told once" do
    incident = incidents(:active_critical_ws1)
    incident.update!(channel_id: "C_RECOVERY")
    postmortem = Postmortem.start_generation!(incident, by: @member)
    adapter = stub
    adapter.expects(:post_postmortem_generation_failed).with { |reason:, retrying:, **| reason == Postmortem::GENERATION_INTERRUPTED && !retrying }.once
    WorkspaceAdapter.stubs(:for).returns(adapter)

    travel Postmortem::GENERATION_STALE_AFTER + 1.minute do
      RecoverySweepJob.perform_now
      RecoverySweepJob.perform_now
    end

    postmortem.reload
    assert postmortem.generation_failed?
    assert_equal Postmortem::INTERRUPTED_NOTE, postmortem.generation_failure_note
    assert Postmortem.start_generation!(incident, by: @member), "Try again starts a new draft"
  end

  test "a map change read whose worker stopped goes to the next full sweep" do
    environment = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare_recovery",
                                                  settings: { "server_url" => "https://mcp.cloudflare.com/mcp" }).integration_environments.create!
    event = ResourceMap::ReceivedEvent.create!(
      workspace: @workspace, integration_environment: environment, provider_event_id: "evt-1", action: ResourceMap::Event::UPDATED,
      scope_key: "zone:1", happened_at: Time.current, received_at: Time.current, outcome: ResourceMap::ReceivedEvent::OUTCOME_READING
    )

    RecoverySweepJob.perform_now
    assert_equal ResourceMap::ReceivedEvent::OUTCOME_READING, event.reload.outcome

    travel ResourceMap::ReceivedEvent::READ_LEASE + 1.minute do
      RecoverySweepJob.perform_now
    end
    assert_equal ResourceMap::ReceivedEvent::OUTCOME_FAILED, event.reload.outcome
  end

  test "it forgets run notes left by jobs that never came back" do
    JobRun.create!(job_id: "old", job_class: InvestigationFixJob.name, created_at: (JobRun::KEPT_FOR + 1.day).ago)
    JobRun.create!(job_id: "recent", job_class: InvestigationFixJob.name, created_at: 1.hour.ago)

    RecoverySweepJob.perform_now

    assert_equal [ "recent" ], JobRun.where(job_id: %w[old recent]).pluck(:job_id)
  end
end
