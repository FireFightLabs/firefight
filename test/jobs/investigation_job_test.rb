require "test_helper"

class InvestigationJobTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @investigation = @workspace.investigations.create!(
      incident: @incident, trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_tokens: 1_000, confidence_threshold: 0.7
    )
  end

  test "the job claims the run before doing anything" do
    InvestigationJob.perform_now(@investigation.id)

    assert_not_nil @investigation.reload.started_at
  end

  test "a run nobody else claimed finishes instead of blocking the incident" do
    InvestigationJob.perform_now(@investigation.id)

    assert_equal Investigation::STATUS_SUCCEEDED, @investigation.reload.status
    assert_not_nil @investigation.completed_at
    assert @investigation.over?
  end

  test "a second pass over the same run changes nothing" do
    InvestigationJob.perform_now(@investigation.id)
    finished_at = @investigation.reload.completed_at

    InvestigationJob.perform_now(@investigation.id)

    assert_equal finished_at, @investigation.reload.completed_at
    assert_equal Investigation::STATUS_SUCCEEDED, @investigation.status
  end

  test "a failure marks the run and re-raises so the queue can retry" do
    Investigation.any_instance.stubs(:claim_running!).raises(RuntimeError, "worker died")

    assert_raises(RuntimeError) { InvestigationJob.perform_now(@investigation.id) }

    @investigation.reload
    assert_equal Investigation::STATUS_FAILED, @investigation.status
    assert_equal "RuntimeError", @investigation.error_summary
  end

  test "a run that is already gone is not retried forever" do
    @investigation.destroy!

    assert_nothing_raised { InvestigationJob.perform_now(@investigation.id) }
  end

  test "the job runs on its own queue" do
    assert_equal "investigations", InvestigationJob.new.queue_name
  end
end
