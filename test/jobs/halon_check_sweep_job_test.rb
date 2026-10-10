require "test_helper"

class HalonCheckSweepJobTest < ActiveJob::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FirefightAi.stubs(:context_window).returns(200_000)
    @check = travel_to(Time.utc(2026, 10, 10, 6, 0)) do
      @workspace.investigation_checks.create!(name: "Disks", kind: Investigation::Check::KIND_DISK, cadence: Investigation::Check::CADENCE_DAILY,
                                              hour: 9, time_zone: "UTC")
    end
  end

  test "a due check starts one scheduled run with the check as its subject, and its schedule moves on" do
    travel_to Time.utc(2026, 10, 10, 9, 2) do
      assert_enqueued_jobs 1, only: InvestigationJob do
        HalonCheckSweepJob.perform_now
        HalonCheckSweepJob.perform_now
      end
    end

    run = @check.investigations.sole
    assert_equal Investigation::TRIGGER_SCHEDULE, run.trigger_source
    assert run.scheduled?
    assert_equal Time.utc(2026, 10, 11, 9, 0), @check.reload.next_run_at
  end

  test "a check that is not due yet waits" do
    travel_to Time.utc(2026, 10, 10, 8, 59) do
      HalonCheckSweepJob.perform_now
    end

    assert_empty @check.investigations
  end

  test "a workspace that cannot run Halon starts nothing, and the schedule still moves on" do
    Investigation.stubs(:start_refusal).returns("AI features are not available.")

    travel_to(Time.utc(2026, 10, 10, 9, 2)) { HalonCheckSweepJob.perform_now }

    assert_empty @check.investigations
    assert_equal Time.utc(2026, 10, 11, 9, 0), @check.reload.next_run_at
  end
end
