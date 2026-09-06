require "test_helper"

class Slack::Messages::ResolutionTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: incident_statuses(:resolved_ws1),
      incident_severity: incident_severities(:minor_ws1),
      name: "Resolved without a write-up",
      is_private: false,
      channel_id: "C_RESOLUTION_TEST",
      resolved_at: Time.current,
      source: Incident::SOURCE_SLACK
    )
  end

  test "offers the write-up and says it draws on the timeline alone when the channel is empty" do
    blocks = Slack::Messages::Resolution.build(@incident, resolved_by_platform_user_id: @member.platform_user_id)

    button = blocks.find { |block| block[:type] == "actions" }[:elements].first
    assert_equal Identifiers::WRITE_POSTMORTEM, button[:action_id]
    assert_equal @incident.id, button[:value]
    assert_match "Drafted from the timeline only", blocks.last[:elements].first[:text]
  end

  test "counts the channel messages the draft will draw on" do
    2.times do |index|
      @incident.incident_transcript_messages.create!(
        workspace: @workspace, message_id: "17000000#{index}.000100", platform_user_id: @member.platform_user_id,
        workspace_membership: @member, content: "Rolled back", posted_at: Time.current
      )
    end

    blocks = Slack::Messages::Resolution.build(@incident, resolved_by_platform_user_id: @member.platform_user_id)

    assert_match "the 2 messages in this channel", blocks.last[:elements].first[:text]
  end

  test "an incident that already has a postmortem gets no button" do
    Postmortem.start_blank!(@incident, by: @member)

    blocks = Slack::Messages::Resolution.build(@incident.reload, resolved_by_platform_user_id: @member.platform_user_id)

    assert_nil blocks.find { |block| block[:type] == "actions" }
    assert_equal "context", blocks.last[:type]
    assert_match "Resolved by", blocks.last[:elements].first[:text]
  end

  test "the announcement thread carries no button" do
    blocks = Slack::Messages::Resolution.announcement_thread(@incident, resolved_by_platform_user_id: @member.platform_user_id)

    assert_nil blocks.find { |block| block[:type] == "actions" }
    assert_equal "header", blocks.first[:type]
  end
end
