require "test_helper"

class Slack::Blocks::AlertTest < ActiveSupport::TestCase
  test "rich, an alert is one alert block at its level" do
    blocks = Slack::Blocks::Alert.new(level: Slack::Blocks::Alert::SUCCESS, text: "Resolved by <@U1> after 1h 12m", emoji: Slack::Emoji::RESOLVED)
                                 .to_blocks(rich: true)

    assert_equal [ { type: "alert", level: "success", text: { type: "mrkdwn", text: "#{Slack::Emoji::RESOLVED} Resolved by <@U1> after 1h 12m" } } ], blocks
  end

  test "plain, it is a bold title opening with its emoji" do
    blocks = Slack::Blocks::Alert.new(level: Slack::Blocks::Alert::WARNING, text: "Reopened by <@U1>", emoji: Slack::Emoji::REOPENED).to_blocks(rich: false)

    assert_equal [ { type: "section", text: { type: "mrkdwn", text: "#{Slack::Emoji::REOPENED}  *Reopened by <@U1>*" } } ], blocks
  end

  test "a text longer than an alert holds is drawn plain rather than cut" do
    text = "x" * 250

    assert_equal "section", Slack::Blocks::Alert.new(level: Slack::Blocks::Alert::INFO, text: text).to_blocks(rich: true).sole[:type]
  end

  test "only Slack's levels are taken" do
    assert_raises(ArgumentError) { Slack::Blocks::Alert.new(level: "loud", text: "x") }
  end
end
