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

  test "the investigate button appears only once the workspace has the flag" do
    incident = incidents(:active_critical_ws1)

    assert_not_includes action_ids(incident), Identifiers::START_INVESTIGATION

    FeatureFlags.enable!(incident.workspace, FeatureFlags::AI_SRE)

    assert_includes action_ids(incident), Identifiers::START_INVESTIGATION
  end

  private

  def action_ids(incident)
    Slack::Messages::QuickActions.buttons(incident).map { |button| button[:action_id] }
  end
end
