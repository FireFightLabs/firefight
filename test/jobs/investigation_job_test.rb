require "test_helper"

class InvestigationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @investigation = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )
    stub_post_message
  end

  def stub_runner(status: Investigation::STATUS_SUCCEEDED, error_summary: nil)
    Investigation::Runner.any_instance.stubs(:run)
      .returns(Investigation::Runner::Result.new(status: status, error_summary: error_summary))
  end

  test "the run gathers the facts before the agent reasons over them" do
    stub_runner

    InvestigationJob.perform_now(@investigation.id)

    assert_equal "INC-001", @investigation.reload.seed_pack.dig("incident", "identifier")
  end

  test "the run posts nothing yet, the finding is what will carry an answer to the channel" do
    stub_runner
    Slack::WorkspaceAdapter.any_instance.expects(:post_message).never

    InvestigationJob.perform_now(@investigation.id)
  end

  test "a run that answers is a success" do
    stub_runner(status: Investigation::STATUS_SUCCEEDED)

    InvestigationJob.perform_now(@investigation.id)

    @investigation.reload
    assert_equal Investigation::STATUS_SUCCEEDED, @investigation.status
    assert_nil @investigation.error_summary
    assert @investigation.over?, "a finished run must not hold the incident's only live slot"
  end

  test "a run that stops without an answer says why" do
    stub_runner(status: Investigation::STATUS_FAILED, error_summary: "Budget spent before it could answer")

    InvestigationJob.perform_now(@investigation.id)

    @investigation.reload
    assert_equal Investigation::STATUS_FAILED, @investigation.status
    assert_equal "Budget spent before it could answer", @investigation.error_summary
  end

  test "a run whose worker was killed is picked up once its lease has run out" do
    @investigation.claim!
    stub_runner

    travel Investigation::LEASE + 1.minute do
      InvestigationJob.perform_now(@investigation.id)
    end

    assert @investigation.reload.over?, "the retry has to finish a run that was already running"
  end

  test "a run another worker holds is left alone" do
    @investigation.claim!
    Investigation::Runner.any_instance.expects(:run).never

    InvestigationJob.perform_now(@investigation.id)

    assert @investigation.reload.live?
  end

  test "a job that lost the run to another worker is dropped rather than retried" do
    Investigation::Runner.any_instance.stubs(:run).raises(Investigation::Runner::LeaseLost, "taken over")

    assert_no_enqueued_jobs { InvestigationJob.perform_now(@investigation.id) }
  end

  test "a second pass over a finished run changes nothing" do
    stub_runner
    InvestigationJob.perform_now(@investigation.id)
    finished_at = @investigation.reload.completed_at

    InvestigationJob.perform_now(@investigation.id)

    assert_equal finished_at, @investigation.reload.completed_at
  end

  test "the seed pack is gathered once, a resumed run reads the facts it already has" do
    stub_runner
    InvestigationJob.perform_now(@investigation.id)
    gathered_at = @investigation.reload.seed_pack["gathered_at"]

    @investigation.update!(status: Investigation::STATUS_PENDING, completed_at: nil, lease_until: nil)
    InvestigationJob.perform_now(@investigation.id)

    assert_equal gathered_at, @investigation.reload.seed_pack["gathered_at"]
  end

  test "an error leaves the run alive and asks the queue to try again" do
    Investigation.any_instance.stubs(:claim!).raises(RuntimeError, "worker died")

    assert_enqueued_with(job: InvestigationJob) { InvestigationJob.perform_now(@investigation.id) }

    assert @investigation.reload.live?, "one stumble must not burn the run"
  end

  test "a run that stumbles after it was claimed is finished by the retry" do
    succeeded = Investigation::Runner::Result.new(status: Investigation::STATUS_SUCCEEDED, error_summary: nil)
    Investigation::Runner.any_instance.stubs(:run).raises(RuntimeError, "deadlock").then.returns(succeeded)

    perform_enqueued_jobs { InvestigationJob.perform_later(@investigation.id) }

    assert_equal Investigation::STATUS_SUCCEEDED, @investigation.reload.status,
                 "the retry has to be able to take a run its own first attempt still held"
  end

  test "an error no retry can fix ends the run at once" do
    Investigation::Runner.any_instance.stubs(:run).raises(FirefightAi::TerminalError.new("too long"))

    assert_no_enqueued_jobs { InvestigationJob.perform_now(@investigation.id) }

    @investigation.reload
    assert_equal Investigation::STATUS_FAILED, @investigation.status
    assert @investigation.over?, "a run that cannot finish must not hold the incident's only live slot"
  end

  test "a run that gave up says so in its thread" do
    @investigation.update!(thread_id: "1700000000.000100")
    Slack::WorkspaceAdapter.any_instance.expects(:post_investigation_stopped).with(
      has_entries(thread_id: "1700000000.000100", reason: InvestigationJob::GAVE_UP)
    )

    InvestigationJob.new(@investigation.id).mark_failed(RuntimeError.new("worker died"))
  end

  test "a thread that cannot be told still leaves the run failed" do
    @investigation.update!(thread_id: "1700000000.000100")
    Slack::WorkspaceAdapter.any_instance.stubs(:post_investigation_stopped).raises(AdapterError, "channel archived")

    InvestigationJob.new(@investigation.id).mark_failed(RuntimeError.new("worker died"))

    assert_equal Investigation::STATUS_FAILED, @investigation.reload.status
  end

  test "the run is marked failed once the retries are gone" do
    InvestigationJob.new(@investigation.id).mark_failed(RuntimeError.new("worker died"))

    @investigation.reload
    assert_equal Investigation::STATUS_FAILED, @investigation.status
    assert_equal "RuntimeError", @investigation.error_summary
  end

  test "a deleted run is discarded rather than raised" do
    @investigation.destroy!

    assert_nothing_raised { InvestigationJob.perform_now(@investigation.id) }
  end

  test "the job runs on its own queue" do
    assert_equal "investigations", InvestigationJob.new.queue_name
  end
end
