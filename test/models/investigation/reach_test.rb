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

  test "a call that names no environment is checked against the environment of the row it runs on" do
    agent = investigation(triggered_by: @member, trigger_source: Investigation::TRIGGER_COMMAND).acting_principal
    dev_only = read_tool("dev_only", catalog_entries(:development_env))
    prod_only = read_tool("prod_only", catalog_entries(:production_env))

    assert_raises(AbilityGateway::Denied) { call(agent, dev_only) }
    assert_equal :read, call(agent, prod_only)
  end

  test "a run reads no connection the person who started it was set to No access on, and is not offered its tools" do
    tool = read_tool("prod_only", catalog_entries(:production_env))
    Ability::Grant.withhold!(workspace: @workspace, principal: @member, role: tool.integration.permission_packs.find_by!(pack: Ability::Role::PACK_READ))
    agent = investigation(triggered_by: @member.reload, trigger_source: Investigation::TRIGGER_COMMAND).acting_principal

    assert_raises(AbilityGateway::Denied) { call(agent, tool, scope: { "environment" => catalog_entries(:production_env).id }) }
    assert_not tool.callable_by?(agent)
    assert tool.callable_by?(SystemAgent.investigator)
  end

  test "a run a service key started reads only what the key was granted" do
    key = api_keys(:read_only_key)
    tool = read_tool("prod_only", catalog_entries(:production_env))
    agent = investigation(triggered_by: key, trigger_source: Investigation::TRIGGER_MCP).acting_principal

    assert_equal key, agent.acting_for
    assert_empty ResourceMap::Resource.visible_to(agent, @workspace)
    assert_raises(AbilityGateway::Denied) { call(agent, tool) }

    limit_map_to(@workspace, key, catalog_entries(:production_env))
    Ability::Grant.grant!(workspace: @workspace, principal: key, target: { role: tool.integration.permission_packs.find_by!(pack: Ability::Role::PACK_READ) })
    assert_equal %w[orders-db web], ResourceMap::Resource.visible_to(agent, @workspace).order(:name).pluck(:name)
    assert_equal :read, call(agent, tool)
  end

  test "a run a service key started stops reaching anything once the key is switched off" do
    key = api_keys(:read_only_key)
    limit_map_to(@workspace, key, catalog_entries(:production_env))
    run = investigation(triggered_by: key, trigger_source: Investigation::TRIGGER_MCP)
    ApiKey.where(id: key.id).update_all(active: false)
    agent = run.acting_principal

    assert_empty ResourceMap::Resource.visible_to(agent, @workspace)
    assert_raises(AbilityGateway::Denied) do
      AbilityGateway.authorize!(principal: agent, action_key: Ability::Action::MAP_READ, workspace: @workspace,
                                scope: { "environment" => catalog_entries(:production_env).id }) { :read }
    end
  end

  test "a run a workflow's own identity started, with nobody behind it, keeps the investigator's reach" do
    workflow = Workflow.create!(workspace: @workspace, name: "Triage", created_by: workspace_memberships(:alice_workspace_one))
    own = @workspace.agents.create!(name: "Triage workflow", slug: "triage_workflow")
    workflow.update!(agent: own)
    agent = investigation(triggered_by: own.reload, trigger_source: Investigation::TRIGGER_WORKFLOW).acting_principal

    assert_nil agent.acting_for
  end

  test "an agent someone made that starts a run bounds it, whatever the trigger" do
    standalone = @workspace.agents.create!(name: "Pager bot", slug: "pager_bot")
    agent = investigation(triggered_by: standalone, trigger_source: Investigation::TRIGGER_WORKFLOW).acting_principal

    assert_equal standalone, agent.acting_for
    assert_empty ResourceMap::Resource.visible_to(agent, @workspace)
  end

  test "a person pressing Run now on a monitoring check bounds that run" do
    agent = investigation(triggered_by: @member, trigger_source: Investigation::TRIGGER_SCHEDULE).acting_principal

    assert_equal @member, agent.acting_for
    assert_equal %w[orders-db web], ResourceMap::Resource.visible_to(agent, @workspace).order(:name).pluck(:name)
  end

  test "a run whose starter's row is gone reaches nothing, never the investigator's whole reach" do
    run = investigation(triggered_by: @member, trigger_source: Investigation::TRIGGER_COMMAND)
    run.update_columns(triggered_by_id: SecureRandom.uuid)
    agent = Investigation.find(run.id).acting_principal

    assert agent.acting_for
    assert_empty ResourceMap::Resource.visible_to(agent, @workspace)
    assert_raises(AbilityGateway::Denied) { call(agent, read_tool("prod_only", catalog_entries(:production_env))) }
    assert_not read_tool("prod_two", catalog_entries(:production_env)).callable_by?(agent)
  end

  test "a fix Halon applies on its own for a run whose starter is gone runs as nobody who can reach anything" do
    run = investigation(triggered_by: @member, trigger_source: Investigation::TRIGGER_COMMAND)
    run.update_columns(triggered_by_id: SecureRandom.uuid)
    finding = Investigation.find(run.id).conclude!(summary: "The pool was too small")
    plan = Investigation::RemediationPlan.new(finding: finding, applied_from: AbilityGateway::SOURCE_INVESTIGATION)

    assert_empty ResourceMap::Resource.visible_to(plan.acting_principal, @workspace)
  end

  private

  def read_tool(name, environment)
    connection = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: name.humanize, slug: name)
    connection.integration_environments.create!(environment: environment)
    connection.tools.create!(name: "list_services", read_only: true, enabled: true)
  end

  def call(agent, tool, scope: {})
    AbilityGateway.authorize!(principal: agent, action_key: tool.action_key, workspace: @workspace, scope: scope) { :read }
  end

  def investigation(triggered_by:, trigger_source:)
    @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: trigger_source, triggered_by: triggered_by, max_turns: 10, max_spend_cents: 400
    )
  end
end
