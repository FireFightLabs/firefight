require "test_helper"

class Commands::AssignRolesTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities,
           :incident_roles, :incident_role_assignments

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "opens the roles modal in an incident channel" do
    stub_open_modal

    assert_nil Commands::AssignRoles.execute(build_command(channel_id: @incident.channel_id))
  end

  test "the modal carries one input per active role, holders preselected" do
    view = Slack::Modals::Roles.build(@incident, @workspace.incident_roles.active.ordered)

    comms = incident_roles(:communications_lead_ws1)
    block = view[:blocks].find { |b| b[:block_id] == Identifiers.role_block_id(comms) }

    assert_equal Identifiers::SET_ROLES_MODAL, view[:callback_id]
    assert_equal comms.name, block[:label][:text]
    assert block[:optional]
    assert_equal workspace_memberships(:bob_workspace_one).platform_user_id, block[:element][:initial_user]
    assert_not view[:blocks].any? { |b| b[:block_id] == Identifiers.role_block_id(incident_roles(:deleted_role)) }
  end

  test "an unassigned role has no preselection" do
    view = Slack::Modals::Roles.build(@incident, @workspace.incident_roles.active.ordered)
    block = view[:blocks].find { |b| b[:block_id] == Identifiers.role_block_id(incident_roles(:incident_lead_ws1)) }

    assert_not block[:element].key?(:initial_user)
  end

  test "returns error when not in an incident channel" do
    result = Commands::AssignRoles.execute(build_command(channel_id: "C_NOT_INCIDENT"))

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "incident channel"
  end

  test "returns error when the workspace has no roles" do
    @workspace.incident_roles.destroy_all

    result = Commands::AssignRoles.execute(build_command(channel_id: @incident.channel_id))

    assert_equal Command::EPHEMERAL, result[:response_type]
    assert_includes result[:text], "No incident roles"
  end

  private

  def build_command(channel_id: "C12345678")
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: "U12345678",
      text: Identifiers::SUBCOMMAND_ROLES,
      trigger_id: "12345.trigger",
      channel_id: channel_id,
      metadata: { command: "/ff" }
    )
  end
end
