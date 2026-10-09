require "test_helper"

class MemoryPostServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    @memory = Chat::Memory.create!(workspace: @workspace, text: "Deploys happen from main", state: Chat::Memory::STATE_UNCONFIRMED)
    @adapter = @workspace.adapter
    Workspace.any_instance.stubs(:adapter).returns(@adapter)
  end

  test "a run on the incident tells the channel in its own thread" do
    run = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 4, max_spend_cents: 400,
                                            channel_id: @incident.channel_id, thread_id: "5.5")
    @adapter.expects(:post_learned_memories).with { |channel_id:, thread_id:, post:|
      channel_id == @incident.channel_id && thread_id == "5.5" && post.kind == Chat::MemoryPost::KIND_LEARNED && post.memories.map(&:id) == [ @memory.id ]
    }.returns(message_id: "5.6", channel_id: @incident.channel_id)

    MemoryNoteJob.perform_now(@memory.id, Chat::MemoryPost::KIND_LEARNED, run)

    assert_equal [ "5.5", "5.6" ], Chat::MemoryPost.find_by!(incident: @incident).values_at(:thread_id, :message_id)
  end

  test "a dashboard chat about the incident tells the channel at the top, since its thread is elsewhere" do
    conversation = Conversation.create!(workspace: @workspace, kind: Conversation::KIND_PERSONAL, subject: @incident, started_by: @member,
                                        max_turns: 10, max_spend_cents: 100)
    @adapter.expects(:post_learned_memories).with { |thread_id:, post:, **| thread_id.nil? && post.kind == Chat::MemoryPost::KIND_DISPUTED }
            .returns(message_id: "6.1", channel_id: @incident.channel_id)

    MemoryPostService.new(@workspace).note!(@memory, kind: Chat::MemoryPost::KIND_DISPUTED, owner: conversation)
  end

  test "a channel archived since keeps the memory on the Memory page, and nothing is posted without an incident" do
    @adapter.stubs(:post_learned_memories).raises(AdapterError::IsArchived)
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)

    assert_nil MemoryPostService.new(@workspace).post!(@incident, [ @memory ], kind: Chat::MemoryPost::KIND_LEARNED)
    assert_nil MemoryPostService.new(@workspace).note!(@memory, kind: Chat::MemoryPost::KIND_LEARNED, owner: conversation)
    assert_not Chat::MemoryPost.exists?(workspace: @workspace)
    assert_equal Chat::Memory::STATE_UNCONFIRMED, @memory.reload.state
  end

  test "what a message shows is said plainly for each state, and a deleted memory drops out" do
    corrected = Chat::Memory.create!(workspace: @workspace, text: "The primary is db-1", state: Chat::Memory::STATE_UNCONFIRMED)
    corrected.reject!(by: @member, reason: "Moved", correction: "The primary is db-2")
    gone = Chat::Memory.create!(workspace: @workspace, text: "Checkout retries twice", state: Chat::Memory::STATE_UNCONFIRMED)
    post = Chat::MemoryPost.create!(workspace: @workspace, incident: @incident, kind: Chat::MemoryPost::KIND_INCIDENT, channel_id: @incident.channel_id,
                                    memory_ids: [ @memory.id, corrected.id, gone.id ])
    gone.destroy!

    shown = MemoryPostService.new(@workspace).shown(post)

    assert_equal [ @memory.id, corrected.id ], shown.memories.map(&:id)
    assert_equal [ Chat::Memory::STATE_REJECTED, @member.display_name, "The primary is db-2" ], shown.memories.last.to_h.values_at(:state, :decided_by, :correction)
    assert_nil shown.memories.first.decided_by
  end

  test "a reminder goes to whoever taught it by direct message, is redrawn in the channel it landed in, and a decision there names the reminder" do
    bob = workspace_memberships(:bob_workspace_one)
    taught = Chat::Memory.create!(workspace: @workspace, text: "Checkout reads from the replica", state: Chat::Memory::STATE_UNCONFIRMED, added_by: bob,
                                  created_at: 10.days.ago)
    @adapter.expects(:post_learned_memories).with { |channel_id:, thread_id:, post:|
      channel_id == bob.platform_user_id && thread_id.nil? && post.kind == Chat::MemoryPost::KIND_REMINDER &&
        post.reminder == MemoryPostService::ShownReminder.new(taught: 1, learned: 0, direct: true) && post.memories.map(&:id) == [ taught.id ]
    }.returns(message_id: "7.1", channel_id: "D42")

    assert_equal 1, MemoryPostService.new(@workspace).remind!

    post = Chat::MemoryPost.reminders.find_by!(recipient: bob)
    assert_equal [ "D42", "7.1" ], post.values_at(:channel_id, :message_id)
    @adapter.expects(:update_learned_memories).with { |channel_id:, message_id:, **| channel_id == "D42" && message_id == "7.1" }
    MemoryPostService.new(@workspace).decide!(reference: post.id, memory_id: taught.id, member: bob, confirmed: false, channel_id: "D42", message_id: "7.1")
    assert_equal "Marked not right in a reminder", taught.reload.state_reason
  end

  test "a reminder an archived incident channel cannot take goes to the admins instead" do
    from_incident = Chat::Memory.create!(workspace: @workspace, text: "A 5xx after a deploy has meant a full disk", state: Chat::Memory::STATE_UNCONFIRMED,
                                         source: @incident, created_at: 10.days.ago)
    @memory.destroy!
    @adapter.expects(:post_learned_memories).with { |channel_id:, **| channel_id == @incident.channel_id }.raises(AdapterError::IsArchived)
    @adapter.expects(:post_learned_memories).with { |channel_id:, post:, **| channel_id == @member.platform_user_id && post.memories.map(&:id) == [ from_incident.id ] }
            .returns(message_id: "8.1", channel_id: "D7")

    assert_equal 1, MemoryPostService.new(@workspace).remind!
    assert_not Chat::MemoryPost.exists?(incident: @incident)
  end
end
