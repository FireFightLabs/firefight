require "test_helper"

class Investigation::CheckTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  def check(**attributes)
    @workspace.investigation_checks.create!(
      name: "Disks", kind: Investigation::Check::KIND_DISK, cadence: Investigation::Check::CADENCE_DAILY, hour: 9, time_zone: "Europe/Belgrade",
      **attributes
    )
  end

  test "a daily check runs next at its hour in its own time zone, tomorrow once today's has passed" do
    travel_to Time.utc(2026, 10, 10, 6, 0) do
      assert_equal Time.utc(2026, 10, 10, 7, 0), check.next_run_at
    end
    travel_to Time.utc(2026, 10, 10, 8, 0) do
      assert_equal Time.utc(2026, 10, 11, 7, 0), check(name: "Later").next_run_at
    end
  end

  test "a weekly check runs on its weekday, and keeps its hour across a daylight saving change" do
    travel_to Time.utc(2026, 10, 21, 12, 0) do
      weekly = check(cadence: Investigation::Check::CADENCE_WEEKLY, weekday: 1)

      # Monday October 26th, the day after Belgrade leaves summer time, at 09:00 local.
      assert_equal Time.utc(2026, 10, 26, 8, 0), weekly.next_run_at
    end
  end

  test "a due check is taken once, and its schedule moves on in the same statement" do
    taken = travel_to(Time.utc(2026, 10, 10, 6, 0)) { check }
    copy = Investigation::Check.find(taken.id)

    travel_to Time.utc(2026, 10, 10, 7, 1) do
      assert taken.claim_due!
      assert_not copy.claim_due!
      assert_equal Time.utc(2026, 10, 11, 7, 0), taken.next_run_at
    end
  end

  test "a disabled check is never due" do
    disabled = travel_to(Time.utc(2026, 10, 10, 6, 0)) { check }
    disabled.disable!

    travel_to(Time.utc(2026, 10, 10, 8, 0)) { assert_empty Investigation::Check.due }
  end

  test "something else needs notes saying what to look at" do
    custom = @workspace.investigation_checks.new(name: "Queue", kind: Investigation::Check::KIND_CUSTOM, cadence: Investigation::Check::CADENCE_DAILY,
                                                 hour: 9, time_zone: "UTC")

    assert_not custom.valid?
    assert_includes custom.errors[:notes], "should say what Halon looks at"
  end

  test "a time zone Firefight does not know is refused" do
    assert_raises(ActiveRecord::RecordInvalid) { check(time_zone: "Mars/Olympus") }
  end

  test "a check that ran keeps its runs, so it is disabled rather than deleted" do
    ran = check
    assert_nil ran.deletion_blocked_reason

    @workspace.investigations.create!(subject: ran, trigger_source: Investigation::TRIGGER_SCHEDULE, max_turns: 10, max_spend_cents: 400,
                                      status: Investigation::STATUS_SUCCEEDED)

    assert_equal "Halon ran Disks 1 time, and those runs stay readable. Disable it instead.",
                 Investigation::Check.with_usage_counts.find(ran.id).deletion_blocked_reason
  end

  test "running now is refused while the check is disabled or already running" do
    running = check
    @workspace.investigations.create!(subject: running, trigger_source: Investigation::TRIGGER_SCHEDULE, max_turns: 10, max_spend_cents: 400)

    assert_equal "Disks is already running. Halon says what it finds when it is done.", running.run_now_blocked_reason

    disabled = check(name: "Off")
    disabled.disable!
    assert_equal "Off is not enabled, so Halon does not run it.", disabled.run_now_blocked_reason
  end
end
