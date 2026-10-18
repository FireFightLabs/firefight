require "test_helper"

# A run a person started reads no further than that person may, as their chat would. A run an alert started keeps the
# investigator's own reach, since nobody asked.
class Investigation::ReachTest < ActiveSupport::TestCase
  include TwoEnvironmentMapHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    build_two_environment_map(@workspace)
    limit_map_to(@workspace, @member, catalog_entries(:production_env))
  end

  test "a run a person started acts as the investigator, within what that person reads of the map" do
    agent = investigation(triggered_by: @member, trigger_source: Investigation::TRIGGER_COMMAND).acting_principal

    assert_equal SystemAgent.investigator, agent
    assert_equal @member, agent.acting_for
    assert_equal %w[orders-db web], ResourceMap::Resource.visible_to(agent, @workspace).order(:name).pluck(:name)
    assert_equal [ catalog_entries(:production_env).id ], ResourceMap::Resource.environments_visible_to(agent, @workspace)
  end

  test "a run an alert started keeps the investigator's whole reach" do
    agent = investigation(triggered_by: nil, trigger_source: Investigation::TRIGGER_ALERT).acting_principal

    assert_nil agent.acting_for
    assert_equal 5, ResourceMap::Resource.visible_to(agent, @workspace).count
  end

  test "a person who reads every environment leaves the investigator's reach as it is" do
    agent = investigation(triggered_by: workspace_memberships(:alice_workspace_one), trigger_source: Investigation::TRIGGER_COMMAND).acting_principal

    assert_equal 5, ResourceMap::Resource.visible_to(agent, @workspace).count
  end

  test "a call aimed at an environment the person may not read is refused and ledgered as the investigator's" do
    agent = investigation(triggered_by: @member, trigger_source: Investigation::TRIGGER_COMMAND).acting_principal

    assert_raises(AbilityGateway::Denied) do
      AbilityGateway.authorize!(principal: agent, action_key: Ability::Action::MAP_READ, workspace: @workspace,
                                scope: { "environment" => catalog_entries(:development_env).id }) { :read }
    end
    assert @workspace.ability_invocations.exists?(decision: Ability::Invocation::DECISION_DENY, action_key: Ability::Action::MAP_READ,
                                                  principal_type: SystemAgent.polymorphic_name, principal_id: SystemAgent.investigator.id)

    assert_equal :read, AbilityGateway.authorize!(principal: agent, action_key: Ability::Action::MAP_READ, workspace: @workspace,
                                                  scope: { "environment" => catalog_entries(:production_env).id }) { :read }
  end

  test "a person narrowed to nothing leaves the run reading none of the map" do
    Ability::Grant.withhold!(workspace: @workspace, principal: @member, action: Ability::Action.system!(Ability::Action::MAP_READ))
    agent = investigation(triggered_by: @member.reload, trigger_source: Investigation::TRIGGER_COMMAND).acting_principal

    assert_empty ResourceMap::Resource.visible_to(agent, @workspace)
  end

  test "a run whose member was removed since reads none of the map" do
    agent = investigation(triggered_by: @member, trigger_source: Investigation::TRIGGER_COMMAND).acting_principal
    @member.update_column(:removed_at, Time.current)

    assert_empty ResourceMap::Resource.visible_to(agent, @workspace)
    assert_raises(AbilityGateway::Denied) do
      AbilityGateway.authorize!(principal: agent, action_key: Ability::Action::MAP_READ, workspace: @workspace,
                                scope: { "environment" => catalog_entries(:production_env).id }) { :read }
    end
  end

  private

  def investigation(triggered_by:, trigger_source:)
    @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: trigger_source, triggered_by: triggered_by, max_turns: 10, max_spend_cents: 400
    )
  end
end
