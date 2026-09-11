require "test_helper"

class Slack::Messages::QuickActionsTest < ActiveSupport::TestCase
  test "an open incident can be resolved with a click" do
    ids = Slack::Messages::QuickActions.buttons(incidents(:active_critical_ws1)).map { |button| button[:action_id] }

    assert_includes ids, Identifiers::RESOLVE_INCIDENT
    assert_equal Identifiers::RESOLVE_INCIDENT, ids.last
  end

  test "a resolved incident offers no buttons at all" do
    assert_empty Slack::Messages::QuickActions.buttons(incidents(:resolved_minor_ws1))
  end

  test "the investigate button is absent until the workspace has the flag" do
    ids = Slack::Messages::QuickActions.buttons(incidents(:active_critical_ws1)).map { |button| button[:action_id] }

    assert_not_includes ids, Identifiers::START_INVESTIGATION
  end

  test "a workspace with the flag can investigate from the message" do
    incident = incidents(:active_critical_ws1)
    FeatureFlags.enable!(incident.workspace, FeatureFlags::AI_SRE)

    ids = Slack::Messages::QuickActions.buttons(incident).map { |button| button[:action_id] }

    assert_includes ids, Identifiers::START_INVESTIGATION
    assert_equal Identifiers::RESOLVE_INCIDENT, ids.last
  end
end
