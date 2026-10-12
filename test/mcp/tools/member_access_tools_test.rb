require "test_helper"

# list_member_access and set_member_access read and set the Who can do what rows through the same model call as the
# dashboard, authorized and in the activity log like every gateway tool.
class Mcp::Tools::MemberAccessToolsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    @northflank.tools.create!(name: "list_services", read_only: true, enabled: true)
    @northflank.tools.create!(name: "restart_service", read_only: false, enabled: true)
    @changes = @northflank.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES)
  end

  test "an admin lists each connection's choices and who reaches it through other access" do
    everywhere = @workspace.ability_roles.find_by!(pack: Ability::Role::PACK_CHANGES_EVERYWHERE)
    Ability::Grant.grant!(workspace: @workspace, principal: @bob, target: { role: everywhere })

    row = call(Mcp::Tools::ListMemberAccess, @admin).structured_content[:connections].sole

    assert_equal "Faylee (Northflank)", row[:connection][:name]
    assert_equal Ability::Role::EVERYONE, row[:read][:choice]
    assert_equal [ Ability::Role::NOBODY, @changes.slug ], row[:change].values_at(:choice, :permission_set)
    assert_equal [ { permission_set: everywhere.slug, name: "Changes everywhere", people: [ { id: @bob.id, name: "Bob Jones" } ] } ],
                 row[:change][:through]
  end

  test "an admin chooses who can change a connection, by email, and the call is in the activity log" do
    answer = call(Mcp::Tools::SetMemberAccess, @admin, permission_set: @changes.slug, choice: Ability::Role::CHOSEN, people: [ @bob.email ])

    assert_not answer.error?
    assert_equal "Bob Jones can change Faylee (Northflank).", answer.structured_content[:notice]
    assert_equal [ { id: @bob.id, name: "Bob Jones" } ], answer.structured_content[:change][:people]
    assert_equal @admin, @changes.grants.find_by!(principal: @bob).granted_by
    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: "permissions.update", principal: @admin)
    assert_equal AbilityGateway::SOURCE_MCP, invocation.source
  end

  test "everyone and nobody set the pack for every member, and a refusal says why" do
    call(Mcp::Tools::SetMemberAccess, @admin, permission_set: @changes.slug, choice: Ability::Role::EVERYONE)
    assert @changes.reload.every_member?

    refused = call(Mcp::Tools::SetMemberAccess, @admin, permission_set: @changes.slug, choice: Ability::Role::CHOSEN, people: [])
    assert refused.error?
    assert_equal "Pick at least one person, or choose Nobody.", refused.content.sole[:text]

    call(Mcp::Tools::SetMemberAccess, @admin, permission_set: @changes.slug, choice: Ability::Role::NOBODY)
    assert_not @changes.reload.every_member?
  end

  test "a member can neither list nor set the rows" do
    assert call(Mcp::Tools::ListMemberAccess, @bob).error?
    assert call(Mcp::Tools::SetMemberAccess, @bob, permission_set: @changes.slug, choice: Ability::Role::EVERYONE).error?
    assert_not @changes.reload.every_member?
  end

  private

  def call(tool, principal, **args)
    Mcp::ToolDispatcher.call(tool: tool, server_context: { workspace: @workspace, principal: principal }, args: args)
  end
end
