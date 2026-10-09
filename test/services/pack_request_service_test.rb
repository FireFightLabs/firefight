require "test_helper"

# A member refused a change asks the admins for the pack, by a click, at most once a day, and an admin gives it.
class PackRequestServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    @northflank.integration_environments.create!
    @restart = @northflank.tools.create!(name: "restart_service", read_only: false, enabled: true)
    @changes = @northflank.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES)
    @conversation = @workspace.conversations.create!(kind: Conversation::KIND_CHANNEL, started_by: @bob, channel_id: "C9", thread_id: "5.5",
                                                     max_turns: 5, max_spend_cents: 100)
    @conversation.chat_record
    @adapter = stub(update_pack_refusal: { success: true }, update_pack_request: { success: true },
                    post_pack_answer_to_user: { channel_id: "D2", message_id: "2.1" }, post_pack_answer: { channel_id: "C9", message_id: "5.7" })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    ConversationChannel.stubs(:broadcast_to)
  end

  test "a refused change leaves one card in the chat and one message in its thread, naming the pack and the admins, and asks nobody" do
    turn = Conversation::Turn.new(@conversation, asker: @bob)
    @adapter.expects(:post_pack_refusal).once.with do |channel_id:, thread_id:, refusal:|
      channel_id == "C9" && thread_id == "5.5" && refusal.body == "It needs the Faylee (Northflank): changes pack. The workspace admin is Alice Smith."
    end.returns(channel_id: "C9", message_id: "5.6")
    @adapter.expects(:post_pack_request_to_user).never

    perform_enqueued_jobs do
      turn.pack_refused!(@restart.action_key, "call_1")
      turn.pack_refused!(@restart.action_key, "call_2")
    end

    refusal = @conversation.chat.pack_refusals.sole
    assert_equal [ "C9", "5.6", "Bob Jones does not have permission to make this change." ], [ refusal.message_channel_id, refusal.message_id, refusal.headline ]
    assert_nil refusal.pack_request.requested_at
    assert_match "The workspace admin is Alice Smith. A card in the chat lets them ask the admins for it.", turn.refusal(@restart.action_key)
  end

  test "asking direct messages every admin once, and asking again within a day, by click or by another refusal, sends nothing" do
    request = Ability::PackRequest.for!(@bob, @changes)
    @adapter.expects(:post_pack_request_to_user).once.with(user_id: @alice.platform_user_id, pack_request: request).returns(channel_id: "D1", message_id: "1.1")

    result = PackRequestService.ask!(request, by: @bob)
    assert_equal [ true, "Asked Alice Smith for Faylee (Northflank): changes." ], [ result.ok, result.words ]

    again = PackRequestService.ask!(request.reload, by: @bob)
    assert_not again.ok
    assert_match "so they are not asked again until a day has passed", again.words
    assert_equal [ { "channel_id" => "D1", "message_id" => "1.1" } ], request.reload.notifications
  end

  test "a day later the same member may ask again" do
    request = Ability::PackRequest.for!(@bob, @changes)
    @adapter.stubs(:post_pack_request_to_user).returns(channel_id: "D1", message_id: "1.1")
    PackRequestService.ask!(request, by: @bob)

    travel 25.hours do
      assert PackRequestService.ask!(request.reload, by: @bob).ok
    end
  end

  test "only the member who was refused can ask" do
    request = Ability::PackRequest.for!(@bob, @changes)
    @adapter.expects(:post_pack_request_to_user).never

    result = PackRequestService.ask!(request, by: @alice)

    assert_equal "Only Bob Jones can ask for this pack, since they were the one refused.", result.words
  end

  test "giving grants the pack the normal way, in every environment, and redraws every admin's message" do
    request = Ability::PackRequest.for!(@bob, @changes)
    @adapter.stubs(:post_pack_request_to_user).returns(channel_id: "D1", message_id: "1.1")
    PackRequestService.ask!(request, by: @bob)
    @adapter.expects(:update_pack_request).with { |channel_id:, message_id:, pack_request:| channel_id == "D1" && message_id == "1.1" && pack_request.given_by == @alice }

    result = PackRequestService.give!(request.reload, by: @alice)

    assert_equal "Bob Jones was given Faylee (Northflank): changes.", result.words
    assert_equal({}, @workspace.ability_grants.find_by!(principal: @bob, role: @changes).scope)
    assert @bob.permitted_to?(@restart.ability_action, @workspace)
    assert_match "already has", PackRequestService.give!(request.reload, by: @alice).words
  end

  test "two admins giving at once give it once, and the one who lost is told it was already answered" do
    request = Ability::PackRequest.for!(@bob, @changes)
    @adapter.stubs(:post_pack_request_to_user).returns(channel_id: "D1", message_id: "1.1")
    PackRequestService.ask!(request, by: @bob)
    late = Ability::PackRequest.find(request.id)
    late.stubs(:give_blocked_reason).returns(nil)
    @adapter.expects(:post_pack_answer_to_user).once.returns(channel_id: "D2", message_id: "2.1")

    assert PackRequestService.give!(request.reload, by: @alice).ok
    result = PackRequestService.give!(late, by: @alice)

    assert_not result.ok
    assert_equal "This request was already answered.", result.words
    assert_equal @alice, request.reload.given_by
  end

  test "a give racing a dismiss loses" do
    request = Ability::PackRequest.for!(@bob, @changes)
    @adapter.stubs(:post_pack_request_to_user).returns(channel_id: "D1", message_id: "1.1")
    PackRequestService.ask!(request, by: @bob)
    late = Ability::PackRequest.find(request.id)
    late.stubs(:give_blocked_reason).returns(nil)

    assert PackRequestService.dismiss!(request.reload, by: @alice).ok

    assert_not PackRequestService.give!(late, by: @alice).ok
    assert_not @workspace.ability_grants.exists?(principal: @bob, role: @changes)
  end

  test "a pack granted on the Permissions screen answers the request and redraws its messages" do
    request = Ability::PackRequest.for!(@bob, @changes)
    @adapter.stubs(:post_pack_request_to_user).returns(channel_id: "D1", message_id: "1.1")
    PackRequestService.ask!(request, by: @bob)
    @adapter.expects(:update_pack_request).once
    @adapter.expects(:post_pack_answer_to_user).once.with { |pack_request:, **| pack_request.answered_by_name == "Alice Smith" }.returns(channel_id: "D2", message_id: "2.1")

    perform_enqueued_jobs { Ability::Grant.grant!(workspace: @workspace, principal: @bob, target: { role: @changes }, granted_by: @alice) }

    assert_not request.reload.waiting?
    assert_empty @workspace.ability_pack_requests.waiting
  end

  test "giving tells the member by direct message and notes it in the thread the change was refused in" do
    request = Ability::PackRequest.for!(@bob, @changes)
    Chat::PackRefusal.create!(chat: @conversation.chat, pack_request: request, message_channel_id: "C9", message_id: "5.6")
    @adapter.stubs(:post_pack_request_to_user).returns(channel_id: "D1", message_id: "1.1")
    PackRequestService.ask!(request, by: @bob)
    @adapter.expects(:post_pack_answer_to_user).once.with do |user_id:, pack_request:|
      user_id == @bob.platform_user_id && Slack::Messages::PackAnswer.fallback(pack_request, direct: true) ==
        "Alice Smith gave you Faylee (Northflank): changes. You can ask Halon again."
    end.returns(channel_id: "D2", message_id: "2.1")
    @adapter.expects(:post_pack_answer).once.with { |channel_id:, thread_id:, **| channel_id == "C9" && thread_id == "5.5" }.returns(channel_id: "C9", message_id: "5.7")

    PackRequestService.give!(request.reload, by: @alice)

    assert_equal "Alice Smith gave Bob Jones this pack. Ask Halon again.", request.refusals.sole.asked_line
  end

  test "a dismissed request tells the member plainly, once" do
    request = Ability::PackRequest.for!(@bob, @changes)
    @adapter.stubs(:post_pack_request_to_user).returns(channel_id: "D1", message_id: "1.1")
    PackRequestService.ask!(request, by: @bob)
    @adapter.expects(:post_pack_answer_to_user).once.with do |pack_request:, **|
      Slack::Messages::PackAnswer.fallback(pack_request, direct: true) == "Alice Smith did not give you Faylee (Northflank): changes. The request was " \
                                                                       "dismissed, so the change still cannot be made. Ask Alice Smith directly if it is still needed."
    end.returns(channel_id: "D2", message_id: "2.1")

    assert PackRequestService.dismiss!(request.reload, by: @alice).ok
    assert_not PackRequestService.dismiss!(request.reload, by: @alice).ok
  end

  test "an admin, a read and a run are never offered a pack" do
    assert_nil Ability::PackRequest.for_refusal(@alice, @restart.ability_action)
    reads = @northflank.tools.create!(name: "list_services", read_only: true, enabled: true)
    assert_nil Ability::PackRequest.for_refusal(@bob, reads.ability_action)
    assert_nil Investigation.new.pack_refused!(@restart.action_key, "call_1")
  end
end
