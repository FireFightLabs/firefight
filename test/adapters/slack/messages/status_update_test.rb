require "test_helper"

class Slack::Messages::StatusUpdateTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
  end

  test "a status update separates its title from its body with a divider" do
    blocks = build(scope: :inline, message: "Rolling back the deploy")

    assert_equal "section", blocks.first[:type]
    assert_equal "divider", blocks.second[:type]
  end

  test "a cancellation takes a header block in the announcement thread" do
    cancel!
    blocks = build(scope: :announcement)

    assert_equal "header", blocks.first[:type]
    assert_equal "divider", blocks.second[:type]
    assert_match "Incident canceled", blocks.first.dig(:text, :text)
  end

  test "a cancellation keeps the identifier and the smaller title in the channel" do
    cancel!
    blocks = build(scope: :inline)

    assert_equal "section", blocks.first[:type]
    assert_match(/#{@incident.identifier} — Incident canceled/, blocks.first.dig(:text, :text))
  end

  test "a multi line update keeps its lines and quotes each one" do
    blocks = build(scope: :inline, message: "Findings so far:\n\n- Probing was observed\n- Requests returned 404")

    assert_equal "> Findings so far:\n>\n> • Probing was observed\n> • Requests returned 404", blocks.third.dig(:text, :text)
  end

  test "an update too long for one section runs on into the next, keeping every line" do
    lines = Array.new(120) { |index| "- Finding #{index} #{"x" * 20}" }
    blocks = build(scope: :inline, message: lines.join("\n"))
    body = blocks.select { |block| block[:type] == "section" && block.dig(:text, :text).start_with?(">") }

    assert_operator body.size, :>, 1
    assert body.all? { |block| block.dig(:text, :text).length <= Slack::Messages::StatusUpdate::SECTION_TEXT_LIMIT }
    assert_equal lines.map { |line| line.sub("- ", "> • ") }, body.flat_map { |block| block.dig(:text, :text).split("\n") }
  end

  private

  def build(scope:, message: nil)
    Slack::Messages::StatusUpdate.build(
      @incident, message: message, updated_by_platform_user_id: "U9", scope: scope
    )
  end

  def cancel!
    canceled = @incident.workspace.incident_statuses.canceled.active.ordered.first
    @incident.update!(incident_status: canceled)
  end
end
