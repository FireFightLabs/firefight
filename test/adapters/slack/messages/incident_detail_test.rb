require "test_helper"

class Slack::Messages::IncidentDetailTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
  end

  # These two used to build the same layout separately and had drifted, the same person was Reporter in one and Declared
  # by in the other.
  test "the announcement and the pinned message describe the incident identically" do
    announcement = detail_lines(Slack::Messages::Announcement.build(@incident))
    pinned = detail_lines(Slack::Messages::QuickActions.build(@incident))

    assert_equal announcement - [ channel_line ], pinned
  end

  test "only the announcement points at the incident channel" do
    assert_includes detail_lines(Slack::Messages::Announcement.build(@incident)), channel_line
    assert_not_includes detail_lines(Slack::Messages::QuickActions.build(@incident)), channel_line
  end

  test "the pinned message ends on its buttons under a divider" do
    pinned = Slack::Messages::QuickActions.build(@incident)

    assert_equal %w[divider actions], pinned.last(2).pluck(:type)
  end

  test "a test incident says so under its title, everywhere it is described" do
    @incident.update!(is_test: true)

    [ Slack::Messages::Announcement.build(@incident), Slack::Messages::QuickActions.build(@incident) ].each do |blocks|
      assert_equal "context", blocks.second[:type]
      assert_equal Slack::Messages::IncidentDetail::TEST_NOTE, blocks.second.dig(:elements, 0, :text)
    end
    assert_nil Slack::Messages::Announcement.build(incidents(:active_major_ws1)).find { |block| block.dig(:elements, 0, :text) == Slack::Messages::IncidentDetail::TEST_NOTE }
  end

  test "a title past Slack's header limit is cut rather than refused" do
    @incident.update!(name: "x" * 300)

    header = Slack::Messages::Announcement.build(@incident).first

    assert_equal Slack::Messages::IncidentDetail::HEADER_LIMIT, header.dig(:text, :text).length
  end

  test "a severity or status name is escaped, so it can never ping the channel" do
    @incident.incident_severity.update_columns(name: "<!channel> Sev")
    @incident.incident_status.update_columns(name: "<!here> Status")

    rows = Slack::Messages::Announcement.build(@incident.reload).filter_map { |block| block.dig(:text, :text) }

    assert_includes rows, "#{Slack::Emoji::SEVERITY} *Severity:* &lt;!channel&gt; Sev"
    assert_includes rows, "#{Slack::Emoji::STATUS} *Status:* &lt;!here&gt; Status"
  end

  test "titles use the middle dot, never a pipe" do
    title = Slack::Messages::IncidentDetail.title_for(@incident)

    assert_includes title, " · "
    assert_not_includes title, "|"
  end

  private

  # Everything up to the trailing divider, where the two messages diverge into their own buttons.
  def detail_lines(blocks)
    blocks.take_while { |block| block[:type] != "actions" }.filter_map { |block| block.dig(:text, :text) }
  end

  def channel_line
    "#{Slack::Emoji::CHANNEL} *Channel:* <##{@incident.channel_id}>"
  end
end
