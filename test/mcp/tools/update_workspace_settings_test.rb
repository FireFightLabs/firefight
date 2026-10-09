require "test_helper"

class Mcp::Tools::UpdateWorkspaceSettingsTest < ActiveSupport::TestCase
  include IssueTrackerTestHelper

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

  test "unconfirmed memories expire after one of the offered windows, and null keeps using them" do
    Mcp::Tools::UpdateWorkspaceSettings.perform_with_principal(workspace: @workspace, principal: @admin, args: { memory_expiry_days: 90 })
    assert_equal 90, @workspace.reload.memory_expiry_days

    refused = Mcp::Tools::UpdateWorkspaceSettings.perform_with_principal(workspace: @workspace, principal: @admin, args: { memory_expiry_days: 45 })
    assert refused.error?
    assert_equal 90, @workspace.reload.memory_expiry_days

    Mcp::Tools::UpdateWorkspaceSettings.perform_with_principal(workspace: @workspace, principal: @admin, args: { memory_expiry_days: nil })
    assert_nil @workspace.reload.memory_expiry_days
  end

  test "retention can be cleared to keep transcripts forever" do
    @workspace.update!(transcript_retention_days: 30)

    Mcp::Tools::UpdateWorkspaceSettings.perform_with_principal(
      workspace: @workspace, principal: @admin, args: { transcript_retention_days: nil }
    )

    assert_nil @workspace.reload.transcript_retention_days
  end

  test "a connected coding agent is chosen by its slug to write code fixes, and null chooses Firefight's own again" do
    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "factory", name: "Factory", slug: "factory")

    response = Mcp::Tools::UpdateWorkspaceSettings.perform_with_principal(workspace: @workspace, principal: @admin, args: { code_fix_agent: "factory" })

    assert_equal "factory", @workspace.reload.code_fix_agent
    assert_equal "factory", response.structured_content[:code_fix_agent]

    Mcp::Tools::UpdateWorkspaceSettings.perform_with_principal(workspace: @workspace, principal: @admin, args: { code_fix_agent: nil })
    assert_nil @workspace.reload.code_fix_agent

    refused = Mcp::Tools::UpdateWorkspaceSettings.perform_with_principal(workspace: @workspace, principal: @admin, args: { code_fix_agent: "nowhere" })
    assert refused.error?
    assert_nil @workspace.reload.code_fix_agent
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

    assert_equal({ transcript_access_enabled: true, transcript_retention_days: 14, archive_channel_delay: @workspace.archive_channel_delay,
                   web_search_enabled: true, halon_regression_enabled: false, memory_expiry_days: nil, code_fix_agent: nil, issue_tracker: nil,
                   issue_creation: Workspace::IssueSync::ISSUE_CREATION_NEVER, issue_tracker_target: {}, issue_webhook_secret_set: false }, body[:settings])
  end

  test "a secret given in a chat is ledgered as its digest, and a held call that gave one never runs from its approval" do
    linear = connect_tracker!(@workspace, provider: "linear")
    conversation = Conversation.start_personal!(workspace: @workspace, member: @admin)
    turn = Conversation::Turn.new(conversation, asker: @admin)
    action = Ability::Action.system!(Ability::Action.system_key(Ability::Action::RESOURCE_WORKSPACE, Ability::Action::ACTION_UPDATE))
    tool = Chat::Tools::Firefight.new(turn, Mcp::Tools::UpdateWorkspaceSettings, action)
    secret = "whsec-said-in-a-chat"

    tool.call(issue_tracker: linear.slug, issue_webhook_secret: secret)

    assert_equal secret, linear.integration_environments.sole.issue_webhook_secret
    ledgered = Ability::Invocation.where(workspace: @workspace, action_key: action.key).pluck(:params)
    assert ledgered.any?
    assert ledgered.none? { |params| params.to_json.include?(secret) }

    said = tool.run_approved(action.key, Mcp::Tools::UpdateWorkspaceSettings.ledger_params(issue_webhook_secret: secret).stringify_keys, approval_id: SecureRandom.uuid)
    assert_match "never keeps issue_webhook_secret", said
    assert_equal secret, linear.integration_environments.sole.issue_webhook_secret
  end
end
