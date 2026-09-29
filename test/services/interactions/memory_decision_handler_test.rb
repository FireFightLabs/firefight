require "test_helper"

class Interactions::MemoryDecisionHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    @memory = Chat::Memory.create!(workspace: @workspace, text: "Sessions live in Redis", state: Chat::Memory::STATE_UNCONFIRMED, source: @incident)
    IncidentLearningService.any_instance.stubs(:redraw)
  end

  test "Confirm vouches for the lesson as whoever pressed it, and Not right rejects it" do
    Interactions::MemoryDecisionHandler.execute(interaction(Identifiers::MEMORY_CONFIRM))
    assert_equal Chat::Memory::STATE_CONFIRMED, @memory.reload.state
    assert_equal @member, @memory.confirmed_by

    other = Chat::Memory.create!(workspace: @workspace, text: "The cause was DNS", state: Chat::Memory::STATE_UNCONFIRMED, source: @incident)
    Interactions::MemoryDecisionHandler.execute(interaction(Identifiers::MEMORY_REJECT, memory: other))
    assert_equal Chat::Memory::STATE_REJECTED, other.reload.state
    assert_equal "Marked not right in #{@incident.identifier}", other.state_reason
  end

  test "a lesson from another incident is not touched by this incident's buttons" do
    @memory.update!(source: incidents(:resolved_minor_ws1))

    Interactions::MemoryDecisionHandler.execute(interaction(Identifiers::MEMORY_CONFIRM))

    assert_equal Chat::Memory::STATE_UNCONFIRMED, @memory.reload.state
  end

  private

  def interaction(action_id, memory: @memory)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id,
                    channel_id: @incident.channel_id, message_id: "1.1", user_id: @member.platform_user_id,
                    action_id: action_id, action_value: "#{@incident.id}:#{memory.id}")
  end
end
