require "test_helper"

# A chat acts as the person who asked, with exactly the reach they have in the dashboard.
class Conversation::TurnTest < ActiveSupport::TestCase
  include IssueTrackerTestHelper

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

  test "a turn reads one catalogue, and builds it again only once a grant or a connection changed during the turn" do
    turn = turn(@member)
    Chat::Tools.expects(:build_catalog).with(turn).times(3).returns([])

    turn.hold_catalog!
    2.times { Chat::Tools.catalog(turn) }
    turn.release_catalog!
    2.times { Chat::Tools.catalog(turn) }

    connect_tracker!(@workspace, provider: "linear")
    2.times { Chat::Tools.catalog(turn) }

    Ability::Grant.grant!(workspace: @workspace, principal: @member, target: { role: @workspace.ability_roles.where.not(pack: nil).first! }, granted_by: @admin)
    Chat::Tools.catalog(turn)
  end

  test "a catalogue built while the turn got ready names a tool switched on during the turn" do
    turn = turn(@member)
    integration = connect_tracker!(@workspace, provider: "linear")
    reader = integration.tools.find_by!(name: "get_issue")
    reader.update!(enabled: false)
    turn.hold_catalog!
    assert_not_includes ready_names(turn), reader.model_facing_name
    turn.release_catalog!

    reader.update!(enabled: true)

    assert_includes ready_names(turn), reader.model_facing_name
  end

  test "a member is told which pack to ask for, the same with the packs read for every tool at once as one by one" do
    integration = connect_tracker!(@workspace, provider: "linear")
    writer = integration.tools.find_by!(name: "save_issue")
    packs = Chat::Tools.changes_packs([ writer ])

    assert_match "Needs the", Chat::Tools.pack_needed(writer)
    assert_equal Chat::Tools.pack_needed(writer), Chat::Tools.pack_needed(writer, packs)
    assert_nil Chat::Tools.pack_needed(integration.tools.find_by!(name: "get_issue"), packs)
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
