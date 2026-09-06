require "test_helper"

class Slack::Messages::WelcomeTest < ActiveSupport::TestCase
  test "a fresh workspace gets three pending steps, a declare button and the command" do
    blocks = Slack::Messages::Welcome.build(WorkspaceOnboarding::STAGE_NONE)

    assert_equal "section", blocks.first[:type]
    assert_equal "divider", blocks.second[:type]
    body = blocks.third.dig(:text, :text)
    assert_equal 3, body.scan(Slack::Messages::Welcome::PENDING).size
    assert_no_match Slack::Messages::Welcome::DONE, body

    declare = blocks.find { |block| block[:type] == "actions" }
    assert_equal Identifiers::DECLARE_INCIDENT_FROM_WELCOME, declare[:elements].first[:action_id]
    assert_equal "Declare a test incident", declare[:elements].first.dig(:text, :text)
    assert_equal "primary", declare[:elements].first[:style]
    assert(blocks.any? { |block| block[:type] == "context" && block[:elements].first[:text].include?("/ff new") })
  end

  test "the declare button goes once the first incident exists and steps tick as it moves" do
    blocks = Slack::Messages::Welcome.build(WorkspaceOnboarding::STAGE_LED)

    body = blocks.third.dig(:text, :text)
    assert_equal 2, body.scan(Slack::Messages::Welcome::DONE).size
    assert_equal 1, body.scan(Slack::Messages::Welcome::PENDING).size
    action_ids = blocks.select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements].map { |element| element[:action_id] } }
    assert_not_includes action_ids, Identifiers::DECLARE_INCIDENT_FROM_WELCOME
    assert_includes action_ids, Identifiers::SHARE_INCIDENTS_CHANNEL
    assert_includes action_ids, Identifiers::PREVIEW_ANNOUNCEMENT
  end

  test "posting messages is coached in the channel, not ticked here, so resolving ticks step three" do
    messaged = Slack::Messages::Welcome.build(WorkspaceOnboarding::STAGE_MESSAGED).third.dig(:text, :text)
    resolved = Slack::Messages::Welcome.build(WorkspaceOnboarding::STAGE_RESOLVED).third.dig(:text, :text)

    assert_equal 2, messaged.scan(Slack::Messages::Welcome::DONE).size
    assert_equal 3, resolved.scan(Slack::Messages::Welcome::DONE).size
    assert_no_match "whole loop", resolved
  end

  test "a completed loop says so" do
    assert_match "whole loop", Slack::Messages::Welcome.build(WorkspaceOnboarding::STAGE_DONE).third.dig(:text, :text)
  end

  test "no actions block is ever empty" do
    [ WorkspaceOnboarding::STAGE_NONE, WorkspaceOnboarding::STAGE_DECLARED, WorkspaceOnboarding::STAGE_DONE ].each do |stage|
      Slack::Messages::Welcome.build(stage).select { |block| block[:type] == "actions" }.each do |block|
        assert block[:elements].any?
      end
    end
  end
end
