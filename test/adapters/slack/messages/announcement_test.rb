require "test_helper"

class Slack::Messages::AnnouncementTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
    Slack::DashboardUrl.stubs(:incident).returns("https://app.example.com/incidents/1")
  end

  test "the announcement is one card: the title, the state on one line, the summary and three buttons" do
    card = Slack::Messages::Announcement.build(@incident, rich: true).first

    assert_equal "card", card[:type]
    assert_equal "#{Slack::Emoji::DECLARED}  #{@incident.identifier} · #{@incident.name}", card.dig(:title, :text)
    assert_equal "#{@incident.incident_severity.name} · #{@incident.incident_status.name}", card.dig(:subtitle, :text)
    assert_equal [ Identifiers::OPEN_INCIDENT_CHANNEL, Identifiers::SUBSCRIBE_INCIDENT, Identifiers::INCIDENT_HOMEPAGE ],
                 card[:actions].map { |button| button[:action_id] }
    assert_equal [ "Join channel", "#{Slack::Emoji::SUBSCRIBE} Subscribe", "Open in Firefight" ], card[:actions].map { |button| button.dig(:text, :text) }
    assert_includes card[:actions].first[:url], @incident.channel_id
  end

  test "no field is a section of its own, so nothing repeats the pinned message block for block" do
    blocks = Slack::Messages::Announcement.build(@incident, rich: false)
    texts = blocks.filter_map { |block| block.dig(:text, :text) }

    assert_empty texts.grep(/\*Severity:\*|\*Status:\*|\*Lead:\*|\*Channel:\*/)
  end

  test "a workspace that does not draw cards gets the same announcement as plain blocks" do
    blocks = Slack::Messages::Announcement.build(@incident, rich: false)

    assert_not blocks.any? { |block| block[:type] == "card" }
    assert_equal "*#{Slack::Emoji::DECLARED}  #{@incident.identifier} · #{@incident.name}*", blocks.first.dig(:text, :text)
    assert_equal "context", blocks.second[:type]
    assert_equal [ Identifiers::OPEN_INCIDENT_CHANNEL, Identifiers::SUBSCRIBE_INCIDENT, Identifiers::INCIDENT_HOMEPAGE ],
                 blocks.find { |block| block[:type] == "actions" }[:elements].map { |button| button[:action_id] }
  end

  test "who declared it follows the card" do
    blocks = Slack::Messages::Announcement.build(@incident, rich: true)

    assert_equal "Declared by #{Slack::Mrkdwn.mention(@incident.declared_by)}", blocks.second.dig(:elements, 0, :text)
  end

  test "the real announcement carries a live Subscribe button naming the incident" do
    button = subscribe_button(Slack::Messages::Announcement.build(@incident, rich: true))

    assert_equal Identifiers::SUBSCRIBE_INCIDENT, button[:action_id]
    assert_equal @incident.id, button[:value]
  end

  test "the install preview keeps its Subscribe button inert" do
    blocks = Slack::Messages::Announcement.build_from(
      title: "[PREVIEW] Website is down", summary: "It is down", severity_name: "Minor",
      status_name: "Investigating", reporter_id: "U1", rich: true
    )

    button = subscribe_button(blocks)

    assert_equal Identifiers::PREVIEW_SUBSCRIBE_DISABLED, button[:action_id]
    assert_nil button[:value]
  end

  private

  def subscribe_button(blocks)
    blocks.flat_map { |block| block[:actions] || block[:elements] || [] }.find { |element| element.dig(:text, :text).to_s.include?("Subscribe") }
  end
end
