require "test_helper"

class AgentChatPackRefusalsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    northflank.tools.create!(name: "restart_service", read_only: false, enabled: true)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @bob)
    request = Ability::PackRequest.for!(@bob, northflank.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES))
    @refusal = Chat::PackRefusal.create!(chat: @conversation.chat_record, pack_request: request, tool_call_id: "call_1")
    @adapter = stub(post_pack_request_to_user: { channel_id: "D1", message_id: "1.1" }, update_pack_refusal: { success: true })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    ConversationChannel.stubs(:broadcast_to)
    sign_in(users(:bob), @workspace)
  end

  test "the chat shows the refusal with Ask an admin, which asks once and then says when" do
    get agent_chat_url(@conversation), headers: inertia_headers
    card = inertia_props["packRefusals"].sole
    assert_equal [ "It needs the Faylee (Northflank): changes pack. The workspace admin is Alice Smith.", nil, nil ],
                 card.values_at("body", "askedLine", "askBlockedReason")

    post agent_chat_pack_refusal_ask_url(@conversation, @refusal)
    assert_equal "Asked Alice Smith for Faylee (Northflank): changes.", flash[:notice]

    @adapter.expects(:post_pack_request_to_user).never
    post agent_chat_pack_refusal_ask_url(@conversation, @refusal)
    assert_match "not asked again until a day has passed", flash[:alert]

    get agent_chat_url(@conversation), headers: inertia_headers
    assert_match "Asked the admins at", inertia_props["packRefusals"].sole["askedLine"]
  end
end
