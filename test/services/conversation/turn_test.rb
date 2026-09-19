require "test_helper"

# A chat acts as the person who asked, with exactly the reach they have in the dashboard.
class Conversation::TurnTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @admin = workspace_memberships(:alice_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
  end

  test "a change is written to the ledger as the person, through the chat" do
    stub_post_message

    firefight_tool(turn(@member), "create_action_item").call(incident: @incident.identifier, description: "Page the DBA")

    row = Ability::Invocation.find_by!(workspace: @workspace, action_key: "incidents.update")
    assert_equal [ WorkspaceMembership.polymorphic_name, @member.id ], [ row.principal_type, row.principal_id ]
    assert_equal AbilityGateway::SOURCE_CONVERSATION, row.source
  end

  test "a member is told who can do what only an admin may" do
    result = grant_tool(turn(@member)).call(principal_kind: "user", principal_id: @member.id, ability: "incidents.read")

    assert_match "cannot use permissions.create", result
    assert_match "workspace admin", result
    assert_empty Ability::Grant.where(principal: @member)
  end

  test "an admin can grant access through chat" do
    grant_tool(turn(@admin)).call(principal_kind: "user", principal_id: @member.id, ability: "alerts.update")

    assert Ability::Grant.where(principal: @member).exists?
  end

  test "a tool that acts as someone credits the person who asked" do
    stub_post_message
    tool = firefight_tool(turn(@member), "create_action_item")

    tool.call(incident: @incident.identifier, description: "Roll back the 14:02 deploy")

    assert_equal @member, @incident.incident_actions.find_by!(description: "Roll back the 14:02 deploy").created_by
  end

  test "a member is offered what a member may do, and an admin everything" do
    member_ready = ready_names(turn(@member))
    admin_ready = ready_names(turn(@admin))

    assert_includes member_ready, "search_incidents"
    assert_not_includes member_ready, "grant_ability"
    assert_includes admin_ready, "grant_ability"
  end

  test "a turn nobody can be credited with does nothing" do
    assert_match "Not allowed", firefight_tool(turn(nil), "search_incidents").call(query: "database")
  end

  private

  def turn(asker) = Conversation::Turn.new(@conversation, asker: asker)

  def ready_names(turn)
    Chat::Tools.catalog(turn).select { |entry| entry.state == Chat::Tools::STATE_READY }.map(&:name)
  end

  def firefight_tool(turn, name)
    tool_class = Mcp::Tools.all.find { |candidate| candidate.name_value == name }
    Chat::Tools::Firefight.new(turn, tool_class, action_for(tool_class))
  end

  def action_for(tool_class)
    Ability::Action.lookup(Ability::Action.system_key(*tool_class.authorization(@workspace, {})), @workspace)
  end

  def grant_tool(turn) = firefight_tool(turn, "grant_ability")
end
