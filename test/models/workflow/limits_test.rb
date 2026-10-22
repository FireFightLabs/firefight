require "test_helper"

class Workflow::LimitsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Busy", created_by: @alice)
  end

  test "a new workflow starts at most 100 runs an hour until someone sets another" do
    assert_equal 100, @workflow.runs_per_hour

    @workflow.runs_per_hour = 0
    assert_not @workflow.valid?
    @workflow.runs_per_hour = Workflow::Limits::RUNS_PER_HOUR.last + 1
    assert_not @workflow.valid?
  end

  test "a run skipped for the limit is counted in the hour it was skipped in, with when the last one was" do
    travel_to Time.zone.parse("2026-10-14 14:05 UTC") do
      @workflow.run_skipped!
      travel 20.minutes
      @workflow.run_skipped!
      travel 1.hour
      @workflow.run_skipped!

      hours = @workflow.recent_skips
      assert_equal [ Time.zone.parse("2026-10-14 15:00 UTC"), Time.zone.parse("2026-10-14 14:00 UTC") ], hours.map(&:hour)
      assert_equal [ 1, 2 ], hours.map(&:count)
      assert_equal Time.zone.parse("2026-10-14 14:25 UTC"), hours.last.last_at
    end
  end

  test "every skipped hour of the week counts, however many hours it skipped in, so the page and the listing agree" do
    travel_to Time.zone.parse("2026-10-14 12:00 UTC") do
      60.times { |hours| @workflow.run_skipped!(at: hours.hours.ago) }

      assert_equal 60, @workflow.recent_skips.size
      assert_equal "60 runs were skipped in the last week because it had already started as many runs in the hour before as it allows.", @workflow.skipped_runs_sentence
      assert_equal 60, Workflow::Listing.for(@workspace).find { |row| row[:name] == "Busy" }[:skipped_runs_last_week]
    end
  end

  test "the page shows a week of skipped hours, and a skip older than that is not shown" do
    travel_to Time.zone.parse("2026-10-01 09:10 UTC") { @workflow.run_skipped! }
    travel_to Time.zone.parse("2026-10-14 09:10 UTC") do
      @workflow.run_skipped!

      assert_equal [ Time.zone.parse("2026-10-14 09:00 UTC") ], @workflow.recent_skips.map(&:hour)
    end
  end
end
