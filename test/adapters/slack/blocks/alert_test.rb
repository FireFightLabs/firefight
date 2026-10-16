require "test_helper"

class Slack::Blocks::AlertTest < ActiveSupport::TestCase
  test "a message gets the line as a section led by its level's emoji, since Slack refuses alert blocks outside modals" do
    alert = Slack::Blocks::Alert.new(level: Slack::Blocks::Alert::LEVEL_SUCCESS, text: "Fix applied  ·  2 of 2 steps done")

    assert_equal [ { type: "section", text: { type: "mrkdwn", text: ":white_check_mark:  Fix applied  ·  2 of 2 steps done" } } ], alert.to_blocks(rich: true)
    assert_equal alert.to_blocks(rich: true), alert.to_blocks(rich: false)
  end

  test "a modal gets Slack's alert block where the workspace shows it, cut to Slack's limit" do
    block = Slack::Blocks::Alert.new(level: Slack::Blocks::Alert::LEVEL_ERROR, text: "x" * 300).to_blocks(rich: true, modal: true).sole

    assert_equal [ "alert", "error", 200 ], [ block[:type], block[:level], block.dig(:text, :text).size ]
    assert_equal "section", Slack::Blocks::Alert.new(level: Slack::Blocks::Alert::LEVEL_DEFAULT, text: "Plain").to_blocks(rich: false, modal: true).sole[:type]
  end

  test "an alert's level is one Slack knows" do
    assert_raises(ArgumentError) { Slack::Blocks::Alert.new(level: "loud", text: "No") }
  end

  test "an alert may lead with the emoji of what happened in place of its level's" do
    alert = Slack::Blocks::Alert.new(level: Slack::Blocks::Alert::LEVEL_WARNING, text: "Reopened by <@U1>", emoji: Slack::Emoji::REOPENED)

    assert_equal "#{Slack::Emoji::REOPENED}  Reopened by <@U1>", alert.to_blocks(rich: true).sole.dig(:text, :text)
  end
end
