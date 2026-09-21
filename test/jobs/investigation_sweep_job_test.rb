require "test_helper"

class InvestigationSweepJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )
  end

  test "a run whose worker died is handed to a new one" do
    @investigation.claim!

    travel Investigation::LEASE + 1.minute do
      assert_enqueued_with(job: InvestigationJob, args: [ @investigation.id ]) { InvestigationSweepJob.perform_now }
    end
  end

  test "a run a worker still holds is left alone" do
    @investigation.claim!

    assert_no_enqueued_jobs(only: InvestigationJob) { InvestigationSweepJob.perform_now }
  end

  test "a run that is over is left alone" do
    @investigation.claim!
    @investigation.finish!(status: Investigation::STATUS_FAILED, error_summary: "RuntimeError")

    travel Investigation::LEASE + 1.minute do
      assert_no_enqueued_jobs(only: InvestigationJob) { InvestigationSweepJob.perform_now }
    end
  end
end
