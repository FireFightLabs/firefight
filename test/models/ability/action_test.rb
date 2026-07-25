require "test_helper"

module Ability
  class ActionTest < ActiveSupport::TestCase
    fixtures :workspaces, :users, :workspace_memberships

    test "sync_system_actions! seeds every resource/action pair idempotently" do
      Ability::Action.sync_system_actions!
      expected = ApiKey::RESOURCES.size * ApiKey::ACTIONS.size
      assert_equal expected, Ability::Action.system_actions.count

      assert_no_difference "Ability::Action.count" do
        Ability::Action.sync_system_actions!
      end
    end

    test "system! maps CRUD verbs to risk levels and reversibility" do
      read = Ability::Action.system!(Ability::Action.system_key(ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_READ))
      update = Ability::Action.system!(Ability::Action.system_key(ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_UPDATE))
      delete = Ability::Action.system!(Ability::Action.system_key(ApiKey::RESOURCE_CATALOG, ApiKey::ACTION_DELETE))

      assert_equal Ability::Action::RISK_READ, read.risk_level
      assert_equal Ability::Action::RISK_WRITE, update.risk_level
      assert_equal Ability::Action::RISK_DESTRUCTIVE, delete.risk_level
      assert read.reversible
      assert_not delete.reversible
    end

    test "system actions must be global and tool actions workspace-scoped" do
      system_action = Ability::Action.new(kind: Ability::Action::KIND_SYSTEM, key: "incidents.read",
                                          risk_level: Ability::Action::RISK_READ,
                                          workspace: workspaces(:slack_workspace_one))
      assert_not system_action.valid?

      tool_action = Ability::Action.new(kind: Ability::Action::KIND_TOOL, key: "datadog.logs.query",
                                        risk_level: Ability::Action::RISK_READ)
      assert_not tool_action.valid?

      tool_action.workspace = workspaces(:slack_workspace_one)
      assert tool_action.valid?
    end

    test "keys must be dotted lowercase identifiers" do
      action = Ability::Action.new(kind: Ability::Action::KIND_SYSTEM, risk_level: Ability::Action::RISK_READ)

      action.key = "incidents"
      assert_not action.valid?

      action.key = "Incidents.Read"
      assert_not action.valid?

      action.key = "datadog_us.logs.query"
      assert action.valid?
    end
  end
end
