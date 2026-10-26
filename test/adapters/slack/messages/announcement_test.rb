require "test_helper"

class Slack::Messages::AnnouncementTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
    Slack::DashboardUrl.stubs(:incident).returns("https://app.example.com/incidents/1")
  end

  test "the announcement is a header, the summary in italics, a divider, then a row per field with its own emoji" do
    blocks = Slack::Messages::Announcement.build(@incident)

    assert_equal "header", blocks.first[:type]
    assert_equal "#{Slack::Emoji::DECLARED} #{@incident.identifier} · #{@incident.name}", blocks.first.dig(:text, :text)
    assert_equal "_#{@incident.summary}_", blocks.second.dig(:text, :text)
    assert_equal "divider", blocks.third[:type]
    assert_equal [
      "#{Slack::Emoji::SEVERITY} *Severity:* #{@incident.incident_severity.name}",
      "#{Slack::Emoji::STATUS} *Status:* #{@incident.incident_status.name}",
      "#{Slack::Emoji::DECLARED_BY} *Declared by:* #{Slack::Mrkdwn.mention(@incident.declared_by)}",
      "#{Slack::Emoji::CHANNEL} *Channel:* <##{@incident.channel_id}>"
    ], rows(blocks)
  end

  test "a lead, custom fields and linked incidents each get their own row" do
    @incident.update!(lead: workspace_memberships(:alice_workspace_one))
    Slack::Messages::Formatting.stubs(:custom_fields_summary).returns(":label: *Region:* eu-west-1")
    Slack::Messages::Formatting.stubs(:relationship_summary).returns(":link:  *Related:* INC-2")

    texts = rows(Slack::Messages::Announcement.build(@incident.reload))

    assert_includes texts, "#{Slack::Emoji::LEAD} *Lead:* #{Slack::Mrkdwn.mention(@incident.lead)}"
    assert_equal [ ":label: *Region:* eu-west-1", ":link:  *Related:* INC-2" ], texts.last(2)
  end

  test "the buttons sit under a divider with their full labels: Join channel, Subscribe and Open in Firefight" do
    blocks = Slack::Messages::Announcement.build(@incident)
    actions = blocks.last

    assert_equal "divider", blocks[-2][:type]
    assert_equal "actions", actions[:type]
    assert_equal [ Identifiers::OPEN_INCIDENT_CHANNEL, Identifiers::SUBSCRIBE_INCIDENT, Identifiers::INCIDENT_HOMEPAGE ], actions[:elements].pluck(:action_id)
    assert_equal [ "Join channel", "#{Slack::Emoji::SUBSCRIBE} Subscribe", "Open in Firefight" ], actions[:elements].map { |button| button.dig(:text, :text) }
    assert_includes actions[:elements].first[:url], @incident.channel_id
  end

  test "an incident with no channel yet offers no Join channel" do
    @incident.update!(channel_id: nil)

    actions = Slack::Messages::Announcement.build(@incident).last

    assert_equal [ Identifiers::SUBSCRIBE_INCIDENT, Identifiers::INCIDENT_HOMEPAGE ], actions[:elements].pluck(:action_id)
  end

  test "a multi line summary is set in italics line by line, since mrkdwn italics end at a line break" do
    @incident.update!(summary: "Checkout fails\n\n- for card payments")

    assert_equal "_Checkout fails_\n\n_• for card payments_", Slack::Messages::Announcement.build(@incident).second.dig(:text, :text)
  end

  test "the real announcement carries a live Subscribe button naming the incident" do
    button = subscribe_button(Slack::Messages::Announcement.build(@incident))

    assert_equal Identifiers::SUBSCRIBE_INCIDENT, button[:action_id]
    assert_equal @incident.id, button[:value]
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

  def rows(blocks)
    blocks.drop_while { |block| block[:type] != "divider" }.drop(1).take_while { |block| block[:type] == "section" }.map { |block| block.dig(:text, :text) }
  end

  def subscribe_button(blocks)
    blocks.find { |block| block[:type] == "actions" }[:elements].find { |element| element.dig(:text, :text).include?("Subscribe") }
  end
end
