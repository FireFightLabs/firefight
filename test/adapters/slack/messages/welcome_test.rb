require "test_helper"

class Slack::Messages::WelcomeTest < ActiveSupport::TestCase
  test "a fresh workspace gets three numbered steps and one row with the declare button first, then the command" do
    blocks = Slack::Messages::Welcome.build(WorkspaceOnboarding::STAGE_NONE)

    assert_equal %w[section divider section actions context], blocks.map { |block| block[:type] }
    body = blocks.third.dig(:text, :text)
    assert_match "1. *Declare an incident.*", body
    assert_match "2. *Work it in that channel.*", body
    assert_match "3. *Resolve it.*", body
    assert_no_match Slack::Messages::Welcome::DONE, body
    assert_no_match ":white_circle:", body

    elements = blocks.fourth[:elements]
    assert_equal [ Identifiers::DECLARE_INCIDENT_FROM_WELCOME, Identifiers::SHARE_INCIDENTS_CHANNEL, Identifiers::PREVIEW_ANNOUNCEMENT ],
                 elements.map { |element| element[:action_id] }
    assert_equal "Declare a test incident", elements.first.dig(:text, :text)
    assert_equal [ "primary", nil, nil ], elements.map { |element| element[:style] }
    assert_equal "Or run `/ff new` in any channel.", blocks.last[:elements].first[:text]
  end

  test "the declare button and the command go once the first incident exists, and finished steps show a check" do
    blocks = Slack::Messages::Welcome.build(WorkspaceOnboarding::STAGE_LED)

    assert_equal %w[section divider section actions], blocks.map { |block| block[:type] }
    body = blocks.third.dig(:text, :text)
    assert_equal 2, body.scan(Slack::Messages::Welcome::DONE).size
    assert_match "#{Slack::Messages::Welcome::DONE} *Declare an incident.*", body
    assert_match "#{Slack::Messages::Welcome::DONE} *Work it in that channel.*", body
    assert_match "3. *Resolve it.*", body
    assert_equal [ Identifiers::SHARE_INCIDENTS_CHANNEL, Identifiers::PREVIEW_ANNOUNCEMENT ], blocks.fourth[:elements].map { |element| element[:action_id] }
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
