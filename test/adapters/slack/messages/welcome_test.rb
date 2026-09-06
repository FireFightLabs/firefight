require "test_helper"

class Slack::Messages::WelcomeTest < ActiveSupport::TestCase
  test "a fresh workspace gets three pending steps, a declare button and the command" do
    blocks = Slack::Messages::Welcome.build(progress)

    assert_equal "section", blocks.first[:type]
    assert_equal "divider", blocks.second[:type]
    body = blocks.third.dig(:text, :text)
    assert_equal 3, body.scan(Slack::Messages::Welcome::PENDING).size
    assert_no_match Slack::Messages::Welcome::DONE, body

    declare = blocks.find { |block| block[:type] == "actions" }
    assert_equal Identifiers::DECLARE_INCIDENT_FROM_WELCOME, declare[:elements].first[:action_id]
    assert_equal "primary", declare[:elements].first[:style]
    assert(blocks.any? { |block| block[:type] == "context" && block[:elements].first[:text].include?("/ff new") })
  end

  test "the declare button goes once the first incident exists and steps tick as it moves" do
    blocks = Slack::Messages::Welcome.build(progress(declared: true, lead_set: true))

    body = blocks.third.dig(:text, :text)
    assert_equal 2, body.scan(Slack::Messages::Welcome::DONE).size
    assert_equal 1, body.scan(Slack::Messages::Welcome::PENDING).size
    action_ids = blocks.select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements].map { |element| element[:action_id] } }
    assert_not_includes action_ids, Identifiers::DECLARE_INCIDENT_FROM_WELCOME
    assert_includes action_ids, Identifiers::SHARE_INCIDENTS_CHANNEL
    assert_includes action_ids, Identifiers::PREVIEW_ANNOUNCEMENT
  end

  test "a completed loop says so" do
    blocks = Slack::Messages::Welcome.build(progress(declared: true, lead_set: true, resolved: true, written_up: true))

    assert_match "whole loop", blocks.third.dig(:text, :text)
  end

  test "a canceled first incident completes the loop without a write-up" do
    done = progress(declared: true, lead_set: true, resolved: true, write_up_dropped: true)

    assert done.complete?
    assert_match "whole loop", Slack::Messages::Welcome.build(done).third.dig(:text, :text)
  end

  test "no actions block is ever empty" do
    [ progress, progress(declared: true) ].each do |state|
      Slack::Messages::Welcome.build(state).select { |block| block[:type] == "actions" }.each do |block|
        assert block[:elements].any?
      end
    end
  end

  private

  def progress(**overrides)
    WorkspaceOnboarding::Progress.new(
      { declared: false, lead_set: false, resolved: false, written_up: false, write_up_dropped: false }.merge(overrides)
    )
  end
end
