require "test_helper"

class Slack::Messages::AnnouncementTest < ActiveSupport::TestCase
  test "the real announcement carries a live Subscribe button naming the incident" do
    incident = incidents(:active_critical_ws1)

    button = subscribe_button(Slack::Messages::Announcement.build(incident))

    assert_equal Identifiers::SUBSCRIBE_INCIDENT, button[:action_id]
    assert_equal incident.id, button[:value]
  end

  test "the install preview keeps its Subscribe button inert" do
    blocks = Slack::Messages::Announcement.build_from(
      title: "[PREVIEW] Website is down", summary: "It is down", severity_name: "Minor",
      status_name: "Investigating", reporter_id: "U1"
    )

    button = subscribe_button(blocks)

    assert_equal Identifiers::PREVIEW_SUBSCRIBE_DISABLED, button[:action_id]
    assert_nil button[:value]
  end

  private

  def subscribe_button(blocks)
    actions = blocks.find { |block| block[:type] == "actions" }
    actions[:elements].find { |element| element[:text][:text].include?("Subscribe") }
  end
end
