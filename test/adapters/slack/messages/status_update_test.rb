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
