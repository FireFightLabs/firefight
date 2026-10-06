require "test_helper"

class Interactions::MemoryDecisionHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    @memory = Chat::Memory.create!(workspace: @workspace, text: "Sessions live in Redis", state: Chat::Memory::STATE_UNCONFIRMED, source: @incident)
    @post = Chat::MemoryPost.create!(workspace: @workspace, incident: @incident, kind: Chat::MemoryPost::KIND_INCIDENT, channel_id: @incident.channel_id,
                                     message_id: "1.1", memory_ids: [ @memory.id ])
    @adapter = @workspace.adapter
    Workspace.any_instance.stubs(:adapter).returns(@adapter)
  end

  test "Confirm vouches for the memory as whoever pressed it, and the message is redrawn with only what it first showed" do
    learned_since = Chat::Memory.create!(workspace: @workspace, text: "The cause was DNS", state: Chat::Memory::STATE_UNCONFIRMED, source: @incident)
    @adapter.expects(:update_learned_memories).with { |channel_id:, message_id:, post:|
      channel_id == @incident.channel_id && message_id == "1.1" && post.memories.map(&:id) == [ @memory.id ] &&
        post.memories.sole.state == Chat::Memory::STATE_CONFIRMED && post.memories.sole.decided_by == @member.display_name
    }

    Interactions::MemoryDecisionHandler.execute(interaction(Identifiers::MEMORY_CONFIRM))

    assert_equal Chat::Memory::STATE_CONFIRMED, @memory.reload.state
    assert_equal @member, @memory.confirmed_by
    assert_equal Chat::Memory::STATE_UNCONFIRMED, learned_since.reload.state
  end

  test "Not right rejects the memory with where it was marked" do
    @adapter.stubs(:update_learned_memories)

    Interactions::MemoryDecisionHandler.execute(interaction(Identifiers::MEMORY_REJECT))

    assert_equal Chat::Memory::STATE_REJECTED, @memory.reload.state
    assert_equal "Marked not right in #{@incident.identifier}", @memory.state_reason
  end

  test "a memory the message does not show is not touched by its buttons" do
    other = Chat::Memory.create!(workspace: @workspace, text: "The cause was DNS", state: Chat::Memory::STATE_UNCONFIRMED, source: @incident)
    @adapter.expects(:update_learned_memories).never

    Interactions::MemoryDecisionHandler.execute(interaction(Identifiers::MEMORY_CONFIRM, memory: other))

    assert_equal Chat::Memory::STATE_UNCONFIRMED, other.reload.state
  end

  test "a message posted before messages were kept still decides on its incident's lessons" do
    @adapter.expects(:update_learned_memories).with { |message_id:, post:, **| message_id == "9.9" && post.memories.map(&:id) == [ @memory.id ] }

    Interactions::MemoryDecisionHandler.execute(interaction(Identifiers::MEMORY_CONFIRM, reference: @incident.id, message_id: "9.9"))

    assert_equal Chat::Memory::STATE_CONFIRMED, @memory.reload.state
  end

  private

  def interaction(action_id, memory: @memory, reference: @post.id, message_id: "1.1")
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id,
                    channel_id: @incident.channel_id, message_id: message_id, user_id: @member.platform_user_id,
                    action_id: action_id, action_value: "#{reference}:#{memory.id}")
  end
end
