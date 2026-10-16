require "test_helper"

class Slack::Messages::IncidentDetailTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
  end

  test "the announcement and the pinned message state the incident with the same line" do
    state = Slack::Messages::IncidentDetail.state_line_for(@incident)
    announcement = Slack::Messages::Announcement.build(@incident, rich: true)
    pinned = Slack::Messages::QuickActions.build(@incident)

    assert_equal state, announcement.first.dig(:subtitle, :text)
    assert pinned.second.dig(:elements, 0, :text).start_with?(state)
  end

  test "the pinned message keeps its buttons but no longer lists each field in a section of its own" do
    pinned = Slack::Messages::QuickActions.build(@incident)

    assert pinned.any? { |block| block[:type] == "actions" }
    assert_empty pinned.filter_map { |block| block.dig(:text, :text) }.grep(/\*Severity:\*|\*Status:\*|\*Lead:\*|\*Declared by:\*/)
  end

  test "a test incident says so, everywhere it is described" do
    @incident.update!(is_test: true)
    note = Slack::Messages::IncidentDetail::TEST_NOTE

    [ Slack::Messages::Announcement.build(@incident, rich: true), Slack::Messages::QuickActions.build(@incident) ].each do |blocks|
      assert blocks.any? { |block| block[:type] == "context" && block.dig(:elements, 0, :text).include?(note) }
    end
    assert_not Slack::Messages::Announcement.build(incidents(:active_major_ws1), rich: true).any? { |block| block.dig(:elements, 0, :text).to_s.include?(note) }
  end

  test "titles and state lines use the middle dot, never a pipe" do
    texts = [ Slack::Messages::IncidentDetail.title_for(@incident), Slack::Messages::IncidentDetail.state_line_for(@incident) ]

    assert texts.all? { |text| text.include?(" · ") }
    assert_not texts.any? { |text| text.include?("|") }
  end
end
