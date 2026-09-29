require "test_helper"

class Chat::Tools::UseSkillTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    @offered = []
  end

  test "every skill of Firefight's own travels in the tool's description with when to use it" do
    description = use_skill.description
    own = Chat::Skill.all.select(&:firefight?)

    own.each { |skill| assert_includes description, "#{skill.name}: #{skill.used_when}" }
    assert_includes description, "firefight incident response:\ndeclaring:"
    assert_equal own.map(&:name), use_skill.parameters_schema.dig("properties", "skill", "enum")
  end

  test "loading a skill says its steps and makes the tools it names callable, and names the ones this person may not use" do
    grant_system!(Ability::Action::RESOURCE_FORMS, Ability::Action::ACTION_READ)

    answer = use_skill.call("skill" => "declaring")

    assert_includes answer, Chat::Skill.find("declaring").steps
    assert_equal [ "get_form" ], @offered.flatten.map(&:name)
    assert_includes answer, "declare_incident is not granted to whoever you are acting as"
  end

  test "a skill that does not exist is answered with the ones that do" do
    answer = use_skill.call("skill" => "juggling")

    assert_includes answer, "There is no skill called juggling"
    assert_empty @offered
  end

  test "a provider's skills are offered only once the workspace has connected that provider" do
    assert_not_includes use_skill.parameters_schema.dig("properties", "skill", "enum"), "northflank_resources"

    connect_northflank(%w[list_resources query_metrics search_logs])

    assert_includes use_skill.parameters_schema.dig("properties", "skill", "enum"), "northflank_resources"
    assert_includes use_skill.description, "northflank telemetry:\nnorthflank_"
  end

  test "a provider's skill makes its tools callable under the names the connection gives them" do
    connect_northflank(%w[describe_resource query_metrics list_containers search_logs])

    answer = use_skill.call("skill" => "northflank_resources")

    assert_includes answer, "Call `northflank_describe_resource` for the plan"
    assert_equal %w[northflank_describe_resource northflank_list_containers northflank_query_metrics northflank_search_logs], @offered.flatten.map(&:name).sort
  end

  test "a provider's tool that is not switched on is named, so the agent says why a step cannot run" do
    connect_northflank(%w[describe_resource query_metrics list_containers])

    answer = use_skill.call("skill" => "northflank_resources")

    assert_includes answer, "search_logs is not switched on for Northflank in this workspace"
  end

  test "a skill names the guides it has, and reading one hands over the provider's text with a note on what can run" do
    @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale")

    steps = use_skill.call("skill" => "planetscale_connections")
    guide = use_skill.call("skill" => "planetscale_connections", "reference" => "postgres/ps-connections.md")

    assert_includes steps, "Guides you can read when you need the detail, with use_skill, this skill and reference: postgres/ps-connections.md"
    assert guide.start_with?(Chat::Tools::UseSkill::GUIDE_NOTE)
    assert_includes guide, "PgBouncer"
    assert_includes use_skill.call("skill" => "planetscale_connections", "reference" => "../../firefight/x.md"), "There is no guide called"
  end

  private

  def connect_northflank(tools)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
    integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    principal = @investigation.acting_principal
    tools.each do |name|
      tool = integration.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object" })
      Ability::Grant.create!(workspace: @workspace, principal: principal, action: tool.reload.ability_action)
    end
    Ability::Resolver.bust!(principal_type: principal.class.polymorphic_name, principal_id: principal.id, workspace_id: @workspace.id)
  end

  def use_skill = Chat::Tools::UseSkill.new(@investigation, offer: ->(tools) { @offered << tools })

  def grant_system!(resource, action)
    principal = @investigation.acting_principal
    Ability::Grant.create!(workspace: @workspace, principal: principal, action: Ability::Action.system!(Ability::Action.system_key(resource, action)))
    Ability::Resolver.bust!(principal_type: principal.class.polymorphic_name, principal_id: principal.id, workspace_id: @workspace.id)
  end
end
