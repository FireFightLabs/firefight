require "test_helper"

# A time in what a confirmation asks is shown in each reader's own time zone, as Slack formats dates.
class Slack::Messages::AgentConfirmationTimesTest < ActiveSupport::TestCase
  test "a time in a confirmation's rows reads in each reader's own zone, with UTC for a client that cannot show it" do
    at = Time.zone.parse("2026-10-13 12:30 UTC")
    confirmation = Struct.new(:tool_name, :asked, :read_heading, :read_rows).new(nil, [ [ "Runs", "Once at #{Chat::TimeToken.for(at)}" ] ], nil, [])

    text = Slack::Messages::AgentConfirmation.detail_blocks(confirmation).sole.dig(:elements, 0, :text)

    assert_equal "Runs: Once at <!date^#{at.to_i}^{date_long_pretty} at {time}|Tue 13 Oct 2026, 12:30 UTC>", text
  end
end
