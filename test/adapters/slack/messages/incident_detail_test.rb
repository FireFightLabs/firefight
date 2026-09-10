require "test_helper"

class Slack::Messages::IncidentDetailTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
  end

  # These two used to build the same layout separately and had drifted, the same person was
  # Reporter in one and Declared by in the other.
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

  # Everything up to the trailing divider, where the two messages diverge into their own buttons.
  def detail_lines(blocks)
    blocks
      .take_while { |block| block[:type] != "actions" }
      .filter_map { |block| block.dig(:text, :text) }
  end

  def channel_line
    ":speech_balloon: *Channel:* <##{@incident.channel_id}>"
  end

  test "a test incident says so under its title, everywhere it is described" do
    incident = incidents(:active_critical_ws1)
    incident.update!(is_test: true)

    announcement = Slack::Messages::Announcement.build(incident)
    quick_actions = Slack::Messages::QuickActions.build(incident)

    [ announcement, quick_actions ].each do |blocks|
      assert_equal "context", blocks.second[:type]
      assert_equal Slack::Messages::IncidentDetail::TEST_NOTE, blocks.second[:elements].first[:text]
    end
    assert_nil Slack::Messages::Announcement.build(incidents(:active_major_ws1)).find { |block| block.dig(:elements, 0, :text) == Slack::Messages::IncidentDetail::TEST_NOTE }
  end
end
