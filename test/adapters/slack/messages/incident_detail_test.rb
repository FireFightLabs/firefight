require "test_helper"

class Slack::Messages::IncidentDetailTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents, :incident_types,
           :catalog_types, :incident_field_definitions, :incident_field_options

  setup do
    @incident = incidents(:active_critical_ws1)
  end

  # These two used to build the same layout separately, and had drifted. The
  # same person was the Reporter in one and Declared by in the other.
  test "the announcement and the pinned message describe the incident identically" do
    announcement = detail_lines(Slack::Messages::Announcement.build(@incident))
    pinned = detail_lines(Slack::Messages::QuickActions.build(@incident))

    assert_equal announcement - [ channel_line ], pinned
  end

  test "only the announcement points at the incident channel" do
    assert_includes detail_lines(Slack::Messages::Announcement.build(@incident)), channel_line
    assert_not_includes detail_lines(Slack::Messages::QuickActions.build(@incident)), channel_line
  end

  private

  # Everything up to the trailing divider, which is where the two messages
  # legitimately diverge into their own buttons.
  def detail_lines(blocks)
    blocks
      .take_while { |block| block[:type] != "actions" }
      .filter_map { |block| block.dig(:text, :text) }
  end

  def channel_line
    ":speech_balloon: *Channel:* <##{@incident.channel_id}>"
  end
end
