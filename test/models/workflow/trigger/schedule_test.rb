require "test_helper"

class Workflow::Trigger::ScheduleTest < ActiveSupport::TestCase
  ZONE = "Europe/Belgrade".freeze

  def schedule(**settings) = { "kind" => "schedule", "time_zone" => ZONE, "inputs" => [] }.merge(settings.stringify_keys)

  def local(text) = ActiveSupport::TimeZone[ZONE].parse(text)

  def next_after(trigger, at) = Workflow::Trigger::Schedule.next_after(trigger, local(at))

  test "every few minutes counts from the start of the day" do
    trigger = schedule(repeat: "minutes", every: 15)

    assert_equal local("2026-10-13 09:15"), next_after(trigger, "2026-10-13 09:07")
    assert_equal local("2026-10-13 09:30"), next_after(trigger, "2026-10-13 09:15")
    assert_equal local("2026-10-14 00:00"), next_after(trigger, "2026-10-13 23:50")
  end

  test "every few hours runs at its minute on hours that divide the day" do
    trigger = schedule(repeat: "hours", every: 6, at: "00:15")

    assert_equal local("2026-10-13 12:15"), next_after(trigger, "2026-10-13 06:20")
    assert_equal local("2026-10-14 00:15"), next_after(trigger, "2026-10-13 18:20")
  end

  test "every weekday at nine skips the weekend, in the trigger's own time zone across a clock change" do
    trigger = schedule(repeat: "days", days: [ 1, 2, 3, 4, 5 ], at: "09:00")

    assert_equal local("2026-10-13 09:00"), next_after(trigger, "2026-10-13 08:59")
    assert_equal local("2026-10-19 09:00"), next_after(trigger, "2026-10-16 09:00")
    assert_equal local("2026-10-26 09:00"), next_after(trigger, "2026-10-23 10:00")
    assert_equal 8, next_after(trigger, "2026-10-23 10:00").utc.hour
  end

  test "once a month on the first Monday or the last Friday" do
    first_monday = schedule(repeat: "monthly", week_of_month: 1, weekday: 1, at: "10:00")
    last_friday = schedule(repeat: "monthly", week_of_month: "last", weekday: 5, at: "16:30")

    assert_equal local("2026-11-02 10:00"), next_after(first_monday, "2026-10-13 09:00")
    assert_equal local("2026-10-30 16:30"), next_after(last_friday, "2026-10-13 09:00")
  end

  test "once at fires one time and never again" do
    trigger = { "kind" => "once_at", "at" => "2026-10-13T14:30", "time_zone" => ZONE }

    assert_equal local("2026-10-13 14:30"), next_after(trigger, "2026-10-13 14:00")
    assert_nil next_after(trigger, "2026-10-13 14:30")
  end

  test "each problem is a sentence" do
    travel_to local("2026-10-13 12:00") do
      assert_equal [ "A schedule repeats every 5 to 720 minutes." ], Workflow::Trigger::Schedule.problems(schedule(repeat: "minutes", every: 1))
      assert_equal [ "A daily schedule needs at least one day of the week." ], Workflow::Trigger::Schedule.problems(schedule(repeat: "days", at: "09:00", days: []))
      assert_equal [ "The trigger needs a time zone Firefight knows, such as Europe/Belgrade." ], Workflow::Trigger::Schedule.problems(schedule(repeat: "minutes", every: 15, time_zone: "Mars/Base"))
      assert_equal [ "Once at is in the past, so it would never run." ],
                   Workflow::Trigger::Schedule.problems({ "kind" => "once_at", "at" => "2026-10-13T11:00", "time_zone" => ZONE })
      assert_empty Workflow::Trigger::Schedule.problems(schedule(repeat: "monthly", week_of_month: "last", weekday: 5, at: "16:30"))
    end
  end

  test "says when it fires the way a person reads it" do
    assert_equal "Every weekday at 09:00 (Europe/Belgrade)", Workflow::Trigger.words(schedule(repeat: "days", days: [ 1, 2, 3, 4, 5 ], at: "09:00"))
    assert_equal "Every 15 minutes", Workflow::Trigger.words(schedule(repeat: "minutes", every: 15))
    assert_equal "The first Monday of every month at 10:00 (Europe/Belgrade)", Workflow::Trigger.words(schedule(repeat: "monthly", week_of_month: 1, weekday: 1, at: "10:00"))
    assert_equal "Once on Tuesday 13 October 2026 at 14:30 (Europe/Belgrade)", Workflow::Trigger.words({ "kind" => "once_at", "at" => "2026-10-13T14:30", "time_zone" => ZONE })
    assert_equal "By hand", Workflow::Trigger.words({ "kind" => "manual" })
  end

  test "a trigger of no known kind is refused" do
    assert_includes Workflow::Trigger.problems({ "kind" => "carrier_pigeon", "inputs" => [] }), "The trigger is a carrier_pigeon trigger, which is not a kind of trigger."
  end
end
