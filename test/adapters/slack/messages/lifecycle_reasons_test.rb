require "test_helper"

# The reason a person gave for a milestone is the message's body: right under the divider, before the fields, and quoted
# on every line so a second line never reads as Firefight's own words.
class Slack::Messages::LifecycleReasonsTest < ActiveSupport::TestCase
  REASON = "Checkout errors are back\nsince the 14:05 deploy".freeze
  QUOTED = "> Checkout errors are back\n> since the 14:05 deploy".freeze

  setup do
    @member = workspace_memberships(:alice_workspace_one)
    @target = workspace_memberships(:bob_workspace_one)
    @incident = Incident.create!(
      workspace: workspaces(:slack_workspace_one), declared_by: @member, incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:minor_ws1), name: "Checkout failing", is_private: false,
      channel_id: "C_REASONS", source: Incident::SOURCE_SLACK
    )
  end

  test "reopen shows the reason as the body in the channel and the announcement thread" do
    channel = Slack::Messages::Reopen.build(@incident, reopened_by_platform_user_id: @member.platform_user_id, reason: REASON)
    thread = Slack::Messages::Reopen.announcement_thread(@incident, reopened_by_platform_user_id: @member.platform_user_id, reason: REASON)

    [ channel, thread ].each { |blocks| assert_body_after_divider(blocks) }
  end

  test "escalation shows the reason as the body before who it went to, in the channel and the direct message" do
    channel = Slack::Messages::Escalation.build(@incident, escalated_by: @member, escalated_to: @target, reason: REASON)
    assert_body_after_divider(channel)
    assert_match "Escalated to", channel[3][:text][:text]

    direct = Slack::Messages::Escalation.direct_message(@incident, escalated_by: @member, escalation_event_id: "event", reason: REASON)
    body = direct.index { |block| block.dig(:text, :text) == QUOTED }
    assert body, "the direct message carries the quoted reason"
    assert body < direct.index { |block| block.dig(:text, :text).to_s.include?("Escalated by") }
  end

  test "a resolution quotes every line of its summary" do
    @incident.update!(summary: REASON)

    assert_body_after_divider(Slack::Messages::Resolution.build(@incident, resolved_by_platform_user_id: @member.platform_user_id))
    assert_body_after_divider(Slack::Messages::Resolution.announcement_thread(@incident, resolved_by_platform_user_id: @member.platform_user_id))
  end

  test "no reason leaves no empty body" do
    blocks = Slack::Messages::Reopen.build(@incident, reopened_by_platform_user_id: @member.platform_user_id, reason: nil)

    assert_equal %w[section divider context], blocks.pluck(:type)
  end

  test "the timeline quotes a reopen's and an escalation's reason the same way" do
    reopened = @incident.incident_events.build(event_type: IncidentEvent::INCIDENT_REOPENED, actor: @member, created_at: Time.current,
                                               metadata: { "reason" => REASON })
    escalated = @incident.incident_events.build(
      event_type: IncidentEvent::INCIDENT_ESCALATED, actor: @member, created_at: Time.current,
      metadata: { "escalated_to_platform_user_id" => @target.platform_user_id, "reason" => REASON }
    )

    assert_includes Slack::IncidentTimelineFormatter.to_block(reopened)[:section][:text][:text], QUOTED
    assert_includes Slack::IncidentTimelineFormatter.to_block(escalated)[:section][:text][:text], "to <@#{@target.platform_user_id}>\n#{QUOTED}"
  end

  private

  def assert_body_after_divider(blocks)
    divider = blocks.index { |block| block[:type] == "divider" }
    assert_equal QUOTED, blocks[divider + 1][:text][:text]
  end
end
