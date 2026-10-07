require "test_helper"

class Slack::Messages::PackRequestMessagesTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    faylee = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    faylee.tools.create!(name: "restart_service", read_only: false, enabled: true)
    @request = Ability::PackRequest.for!(@bob, faylee.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES))
  end

  test "the admin's message carries Give pack until the pack is given, then says by whom" do
    blocks = Slack::Messages::PackRequest.build(@request)
    assert_equal ":key:  *Bob Jones asks for the Faylee (Northflank): changes pack*", blocks.first.dig(:text, :text)
    assert_equal [ Identifiers::PACK_REQUEST_GIVE ], blocks.last[:elements].filter_map { |element| element[:action_id] }

    @request.update_columns(given_at: Time.current, given_by_id: workspace_memberships(:alice_workspace_one).id)
    blocks = Slack::Messages::PackRequest.build(@request.reload)
    assert_equal "Given by Alice Smith.", blocks.last[:elements].sole[:text]
  end

  test "the thread's refusal carries Ask an admin until the admins were asked" do
    conversation = @workspace.conversations.create!(kind: Conversation::KIND_CHANNEL, started_by: @bob, channel_id: "C9", thread_id: "5.5",
                                                    max_turns: 5, max_spend_cents: 100)
    refusal = Chat::PackRefusal.create!(chat: conversation.chat_record, pack_request: @request)

    assert_equal Identifiers::PACK_REQUEST_ASK, Slack::Messages::PackRefusal.build(refusal).last[:elements].sole[:action_id]

    @request.update_columns(requested_at: Time.current)
    assert_match "Asked the admins at", Slack::Messages::PackRefusal.build(refusal.reload).last[:elements].sole[:text]
  end
end
