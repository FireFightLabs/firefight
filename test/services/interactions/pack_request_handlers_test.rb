require "test_helper"

class Interactions::PackRequestHandlersTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    northflank.tools.create!(name: "restart_service", read_only: false, enabled: true)
    @request = Ability::PackRequest.for!(@bob, northflank.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES))
    @adapter = stub(post_pack_request_to_user: { channel_id: "D1", message_id: "1.1" }, update_pack_request: { success: true },
                    update_pack_refusal: { success: true }, post_pack_answer_to_user: { channel_id: "D2", message_id: "2.1" })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    ConversationChannel.stubs(:broadcast_to)
  end

  test "Ask an admin in the thread asks the admins and tells only whoever pressed it" do
    @adapter.expects(:post_ephemeral).with(channel_id: "C9", user_id: @bob.platform_user_id, text: "Asked Alice Smith for Faylee (Northflank): changes.")

    InteractionDispatcher.dispatch(press(Identifiers::PACK_REQUEST_ASK, @bob))

    assert @request.reload.waiting?
  end

  test "Give pack in an admin's direct messages grants it through the gateway, and a member pressing it is refused" do
    @adapter.stubs(:post_ephemeral)
    PackRequestService.ask!(@request, by: @bob)

    InteractionDispatcher.dispatch(press(Identifiers::PACK_REQUEST_GIVE, @bob))
    assert_not @workspace.ability_grants.exists?(principal: @bob, role: @request.role)
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: "permissions.create", decision: Ability::Invocation::DECISION_DENY)

    InteractionDispatcher.dispatch(press(Identifiers::PACK_REQUEST_GIVE, @alice))
    assert @workspace.ability_grants.exists?(principal: @bob, role: @request.role)
    assert_equal @alice, @request.reload.given_by
  end

  private

  def press(action_id, member)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: member.platform_user_id,
                    action_id: action_id, action_value: @request.id, channel_id: "C9")
  end
end
