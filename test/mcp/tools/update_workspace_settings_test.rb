require "test_helper"

class Mcp::Tools::UpdateWorkspaceSettingsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @workspace.update!(transcript_access_enabled: false, transcript_retention_days: nil)
  end

  test "an admin turns transcript access on, and the answer says what changed" do
    response = Mcp::Tools::UpdateWorkspaceSettings.perform_with_principal(
      workspace: @workspace, principal: @admin, args: { transcript_access_enabled: true }
    )

    assert @workspace.reload.transcript_access_enabled
    assert_equal true, response.structured_content[:transcript_access_enabled]
    assert_equal [ "transcript_access_enabled" ], response.structured_content[:changed]
  end

  test "each setting can be changed on its own, and the others are left alone" do
    @workspace.update!(transcript_access_enabled: true)

    Mcp::Tools::UpdateWorkspaceSettings.perform_with_principal(
      workspace: @workspace, principal: @admin, args: { transcript_retention_days: 30 }
    )

    @workspace.reload
    assert @workspace.transcript_access_enabled
    assert_equal 30, @workspace.transcript_retention_days
  end

  test "retention can be cleared to keep transcripts forever" do
    @workspace.update!(transcript_retention_days: 30)

    Mcp::Tools::UpdateWorkspaceSettings.perform_with_principal(
      workspace: @workspace, principal: @admin, args: { transcript_retention_days: nil }
    )

    assert_nil @workspace.reload.transcript_retention_days
  end

  test "the archive delay takes the same choices as the settings page, by value or label" do
    Mcp::Tools::UpdateWorkspaceSettings.perform_with_principal(
      workspace: @workspace, principal: @admin, args: { archive_channel_delay: "1 hour" }
    )

    assert_equal "60", @workspace.reload.archive_channel_delay
  end

  test "a value the settings page would refuse is refused here, with the reason" do
    response = Mcp::Tools::UpdateWorkspaceSettings.perform_with_principal(
      workspace: @workspace, principal: @admin, args: { transcript_retention_days: -3 }
    )

    assert response.error?
    assert_match "retention", response.content.first[:text].downcase
    assert_nil @workspace.reload.transcript_retention_days
  end

  test "a call that changes nothing says so rather than pretending" do
    response = Mcp::Tools::UpdateWorkspaceSettings.perform_with_principal(workspace: @workspace, principal: @admin, args: {})

    assert response.error?
    assert_match "Give at least one", response.content.first[:text]
  end

  test "it needs the workspace permission, which only admins hold" do
    assert_equal [ Ability::Action::RESOURCE_WORKSPACE, Ability::Action::ACTION_UPDATE ],
                 Mcp::Tools::UpdateWorkspaceSettings.authorization(@workspace, {})
  end

  test "the archive delay parameter lists the choices, so a model picks one that exists" do
    description = Mcp::Tools::UpdateWorkspaceSettings.input_schema_value.to_h.dig(:properties, :archive_channel_delay, :description)

    assert_match "60 (1 hour)", description
    assert_match "never (Never)", description
  end

  test "a chat asks before changing a workspace setting, whoever asked" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @admin)
    turn = Conversation::Turn.new(conversation, asker: @admin)
    action = Ability::Action.system!(Ability::Action.system_key(Ability::Action::RESOURCE_WORKSPACE, Ability::Action::ACTION_UPDATE))

    assert Chat::Tools::Firefight.new(turn, Mcp::Tools::UpdateWorkspaceSettings, action).requires_approval?
  end

  test "the settings are read back with the rest of the workspace's configuration" do
    @workspace.update!(transcript_access_enabled: true, transcript_retention_days: 14)

    body = Mcp::Tools::GetWorkspaceConfig.perform_with_principal(workspace: @workspace, principal: @admin, args: {}).structured_content

    assert_equal({ transcript_access_enabled: true, transcript_retention_days: 14, archive_channel_delay: @workspace.archive_channel_delay }, body[:settings])
  end
end
