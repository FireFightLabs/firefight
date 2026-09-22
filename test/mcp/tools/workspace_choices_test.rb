require "test_helper"

# The values a tool accepts for a role, a severity or a status are the workspace's own, so they are
# put in the tool's parameter list when it is offered. A model then picks from what exists rather
# than guessing a name.
class Mcp::Tools::WorkspaceChoicesTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "a role parameter lists the workspace's roles, slug and name, in the order the workspace shows them" do
    description = Mcp::Tools::AssignIncidentRole.schema_for(@workspace).dig(:properties, :role, :description)

    @workspace.incident_roles.active.ordered.each do |role|
      assert_match "#{role.slug} (#{role.name})", description
    end
    assert_match "One of", description
  end

  test "a workspace with one role is told there is one, so a model does not ask which" do
    @workspace.incident_roles.active.where.not(slug: "incident_lead").update_all(deleted_at: Time.current)

    description = Mcp::Tools::AssignIncidentRole.schema_for(@workspace).dig(:properties, :role, :description)

    assert_match "The only one", description
  end

  test "severity and status filters on a search list the workspace's own" do
    schema = Mcp::Tools::SearchIncidents.schema_for(@workspace)

    assert_match "critical (Critical)", schema.dig(:properties, :severity, :description)
    assert_match @workspace.incident_statuses.active.first.slug, schema.dig(:properties, :status, :description)
  end

  test "a person parameter says me is accepted" do
    assert_match "\"me\"", Mcp::Tools::AssignIncidentRole.schema_for(@workspace).dig(:properties, :member, :description)
  end

  test "a tool with no workspace choices is offered unchanged" do
    assert_equal Mcp::Tools::GetIncident.input_schema_value.to_h, Mcp::Tools::GetIncident.schema_for(@workspace)
  end

  test "the choices are what the workspace has now, not what it had when the class loaded" do
    @workspace.incident_roles.create!(name: "Scribe", slug: "scribe", position: @workspace.incident_roles.maximum(:position) + 1)

    assert_match "scribe (Scribe)", Mcp::Tools::AssignIncidentRole.schema_for(@workspace).dig(:properties, :role, :description)
  end

  test "the agent is handed the workspace's choices, and an outside MCP client is handed the same" do
    investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    tool = Chat::Tools::Firefight.new(investigation, Mcp::Tools::AssignIncidentRole, nil)

    assert_equal Mcp::Tools::AssignIncidentRole.schema_for(@workspace), tool.parameters_schema
    assert_match "incident_lead", Mcp::Tools::AssignIncidentRole.definition_for(@workspace)[:inputSchema].dig(:properties, :role, :description)
  end
end
