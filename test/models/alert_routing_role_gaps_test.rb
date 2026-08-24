require "test_helper"

class AlertRoutingRoleGapsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(
      priority: 1, conditions: [],
      outcome: {
        "action" => PolicyRule::AlertRoutingOutcome::ACTION_AUTO_CREATE,
        "invite" => [ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM, "of" => "service" } ]
      }
    )
    policy.policy_rules.create!(
      priority: 2, conditions: [],
      outcome: {
        "action" => PolicyRule::AlertRoutingOutcome::ACTION_NOTIFY_ONLY,
        "notify" => { "type" => PolicyRule::AlertRoutingOutcome::TARGET_TEAM, "entry_id" => catalog_entries(:platform_team).id }
      }
    )
  end

  test "no warnings while the team type has its roles tagged" do
    assert_empty Alert::RoutingRoleGaps.for(@workspace)
  end

  test "warns when paging rules exist and no attribute holds Members or Manager" do
    catalog_attribute_definitions(:team_members).update_column(:role, nil)
    catalog_attribute_definitions(:team_manager).update_column(:role, nil)

    warnings = Alert::RoutingRoleGaps.for(@workspace)
    assert warnings.any? { |sentence| sentence.include?("Members or Manager") }
  end

  test "a mapped manager alone keeps paging possible, so no warning" do
    catalog_attribute_definitions(:team_members).update_column(:role, nil)

    warnings = Alert::RoutingRoleGaps.for(@workspace)
    assert_not warnings.any? { |sentence| sentence.include?("Members or Manager") }
  end

  test "warns when notify rules exist and no attribute holds the notification channel" do
    catalog_attribute_definitions(:team_slack_channel).update_column(:role, nil)
    catalog_attribute_definitions(:service_slack_channel).update_column(:role, nil)

    warnings = Alert::RoutingRoleGaps.for(@workspace)
    assert warnings.any? { |sentence| sentence.include?("Notification channel") }
  end

  test "rules that never target a team produce no warnings" do
    PolicyRule.joins(:policy).where(policies: { workspace_id: @workspace.id }).delete_all
    @workspace.policies.find_by!(domain: Policy::DOMAIN_ALERT_ROUTING).policy_rules.create!(
      priority: 1, conditions: [],
      outcome: { "action" => PolicyRule::AlertRoutingOutcome::ACTION_DROP }
    )
    catalog_attribute_definitions(:team_members).update_column(:role, nil)
    catalog_attribute_definitions(:team_manager).update_column(:role, nil)

    assert_empty Alert::RoutingRoleGaps.for(@workspace)
  end
end
