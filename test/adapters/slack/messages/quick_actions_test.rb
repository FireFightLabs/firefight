require "test_helper"

class Slack::Messages::QuickActionsTest < ActiveSupport::TestCase
  test "an open incident can be resolved with a click" do
    ids = action_ids(incidents(:active_critical_ws1))

    assert_includes ids, Identifiers::RESOLVE_INCIDENT
    assert_equal Identifiers::RESOLVE_INCIDENT, ids.last
  end

  test "a resolved incident offers no buttons at all" do
    assert_empty Slack::Messages::QuickActions.buttons(incidents(:resolved_minor_ws1))
  end

  test "every workspace is offered the investigate button" do
    assert_includes action_ids(incidents(:active_critical_ws1)), Identifiers::START_INVESTIGATION
  end

  test "a workspace whose plan does not include AI is not offered it" do
    deny_entitlements!

    assert_not_includes action_ids(incidents(:active_critical_ws1)), Identifiers::START_INVESTIGATION
  end

  private

  def action_ids(incident)
    Slack::Messages::QuickActions.buttons(incident).map { |button| button[:action_id] }
  end
end
