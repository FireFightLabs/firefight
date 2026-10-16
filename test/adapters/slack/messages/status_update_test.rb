require "test_helper"

class Slack::Messages::StatusUpdateTest < ActiveSupport::TestCase
  setup do
    @incident = incidents(:active_critical_ws1)
  end

  test "an update is a card: the title, what changed as its subtitle and the update as its body, with who wrote it under it" do
    blocks = build(scope: :inline, message: "Rolling back the [deploy](https://ci.example.com/run/1)", previous_status_name: "Identified", rich: true)
    card = blocks.first

    assert_equal "card", card[:type]
    assert_equal "#{Slack::Emoji::UPDATED} #{@incident.identifier} · Incident updated", card.dig(:title, :text)
    assert_equal "Severity: *#{@incident.incident_severity.name}* · Status: ~Identified~ → *#{@incident.incident_status.name}*", card.dig(:subtitle, :text)
    assert_equal "Rolling back the <https://ci.example.com/run/1|deploy>", card.dig(:body, :text)
    assert_equal "context", blocks.last[:type]
    assert_match "Updated by <@U9>", blocks.last.dig(:elements, 0, :text)
  end

  test "the same update reads as a plain message where cards are not drawn, its title apart from its body by a divider" do
    blocks = build(scope: :inline, message: "Rolling back the deploy")

    assert_equal %w[section context divider section context], blocks.pluck(:type)
    assert_equal "#{Slack::Emoji::UPDATED}  *#{@incident.identifier} · Incident updated*", blocks.first.dig(:text, :text)
    assert_equal "> Rolling back the deploy", blocks.fourth.dig(:text, :text)
  end

  test "a cancellation never reads as an update" do
    cancel!

    assert_equal "#{Slack::Emoji::CANCELED} Incident canceled", build(scope: :announcement, rich: true).first.dig(:title, :text)
    assert_match "#{@incident.identifier} · Incident canceled", build(scope: :inline).first.dig(:text, :text)
  end

  test "a multi line update keeps its lines and quotes each one" do
    blocks = build(scope: :inline, message: "Findings so far:\n\n- Probing was observed\n- Requests returned 404")

    assert_equal "> Findings so far:\n>\n> • Probing was observed\n> • Requests returned 404", blocks.fourth.dig(:text, :text)
  end

  test "an update too long for one section runs on into the next, keeping every line" do
    lines = Array.new(120) { |index| "- Finding #{index} #{"x" * 20}" }
    blocks = build(scope: :inline, message: lines.join("\n"), rich: true)
    body = blocks.select { |block| block[:type] == "section" && block.dig(:text, :text).start_with?(">") }

    assert_equal "card", blocks.first[:type]
    assert_nil blocks.first[:body], "a body longer than a card holds follows it instead"
    assert_operator body.size, :>, 1
    assert body.all? { |block| block.dig(:text, :text).length <= Slack::Messages::Formatting::SECTION_TEXT_LIMIT }
    assert_equal lines.map { |line| line.sub("- ", "> • ") }, body.flat_map { |block| block.dig(:text, :text).split("\n") }
  end

  test "no pipe separates anything" do
    @incident.update!(next_update_at: 1.hour.from_now)

    assert_not build(scope: :inline, message: "x", rich: true).to_s.include?(" | ")
  end

  private

  def build(scope:, message: nil, rich: false, previous_status_name: nil)
    Slack::Messages::StatusUpdate.build(
      @incident, message: message, updated_by_platform_user_id: "U9", scope: scope, rich: rich, previous_status_name: previous_status_name
    )
  end

  def cancel!
    canceled = @incident.workspace.incident_statuses.canceled.active.ordered.first
    @incident.update!(incident_status: canceled)
  end
end
