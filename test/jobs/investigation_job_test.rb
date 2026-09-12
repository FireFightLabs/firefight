require "test_helper"

class InvestigationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @investigation = @workspace.investigations.create!(
      incident: @incident, trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )
  end

  test "a run with nothing to do says so rather than claiming success" do
    InvestigationJob.perform_now(@investigation.id)

    @investigation.reload
    assert_equal Investigation::STATUS_CANCELED, @investigation.status
    assert_equal "Nothing to run yet", @investigation.error_summary
    assert_not_nil @investigation.completed_at
    assert @investigation.over?, "a finished run must not hold the incident's only live slot"
  end

  test "a run left running by a killed worker is picked up, not abandoned" do
    @investigation.claim!

    InvestigationJob.perform_now(@investigation.id)

    assert @investigation.reload.over?, "the retry has to finish a run that was already running"
  end

  test "a second pass over a finished run changes nothing" do
    InvestigationJob.perform_now(@investigation.id)
    finished_at = @investigation.reload.completed_at

    InvestigationJob.perform_now(@investigation.id)

    assert_equal finished_at, @investigation.reload.completed_at
    assert_equal Investigation::STATUS_CANCELED, @investigation.status
  end

  test "an error leaves the run alive and asks the queue to try again" do
    Investigation.any_instance.stubs(:claim!).raises(RuntimeError, "worker died")

    assert_enqueued_with(job: InvestigationJob) { InvestigationJob.perform_now(@investigation.id) }

    assert @investigation.reload.live?, "one stumble must not burn the run"
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
