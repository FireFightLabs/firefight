require "test_helper"

class Interactions::CorrectMemoryHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    @memory = Chat::Memory.create!(workspace: @workspace, text: "The cause was DNS", state: Chat::Memory::STATE_DISPUTED, source: @incident,
                                   state_reason: "The resolver answered fine")
    @post = Chat::MemoryPost.create!(workspace: @workspace, incident: @incident, kind: Chat::MemoryPost::KIND_DISPUTED, channel_id: @incident.channel_id,
                                     message_id: "1.1", memory_ids: [ @memory.id ])
    @adapter = @workspace.adapter
    Workspace.any_instance.stubs(:adapter).returns(@adapter)
  end

  test "Correct opens the form holding the memory, at once, so the trigger has not expired" do
    @adapter.expects(:open_memory_correction_modal).with { |trigger_id:, post_id:, memory:|
      trigger_id == "T1" && post_id == @post.id && memory.text == "The cause was DNS"
    }

    Interactions::OpenMemoryCorrectionHandler.execute(
      Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, trigger_id: "T1",
                      user_id: @member.platform_user_id, action_id: Identifiers::MEMORY_CORRECT, action_value: "#{@post.id}:#{@memory.id}")
    )
  end

  test "opening the form declares a read and its submission the write, so an approval rule holds the correction and never the click" do
    assert_equal [ Ability::Action::RESOURCE_MEMORY, Ability::Action::ACTION_READ ], Interactions::OpenMemoryCorrectionHandler.authorization
    assert_equal [ Ability::Action::RESOURCE_MEMORY, Ability::Action::ACTION_UPDATE ], Interactions::CorrectMemoryHandler.authorization
  end

  test "the form's correction replaces the memory as confirmed by whoever wrote it, and the message is redrawn" do
    @adapter.expects(:update_learned_memories).with { |post:, **| post.memories.sole.correction == "The cause was the connection pool" }

    assert_nil Interactions::CorrectMemoryHandler.execute(submission("The cause was the connection pool", "It was the pool"))

    @memory.reload
    assert_equal [ Chat::Memory::STATE_REJECTED, @member, "It was the pool" ], @memory.values_at(:state, :rejected_by, :state_reason)
    assert_equal [ "The cause was the connection pool", Chat::Memory::STATE_CONFIRMED, @member ], @memory.replaced_by.values_at(:text, :state, :confirmed_by)
  end

  test "an empty correction or one holding a secret keeps the form open with why" do
    @adapter.expects(:update_learned_memories).never

    assert_equal "Write what is right instead.", error_of(Interactions::CorrectMemoryHandler.execute(submission("", "")))
    assert_match "looks like it holds a secret", error_of(Interactions::CorrectMemoryHandler.execute(submission("Prod is postgres://app:hunter2@db:5432/app", "")))
    assert_equal Chat::Memory::STATE_DISPUTED, @memory.reload.state
  end

  private

  def submission(correction, reason)
    Interaction.new(
      platform: Platforms::SLACK, type: Interaction::VIEW_SUBMISSION, team_id: @workspace.platform_id, user_id: @member.platform_user_id,
      callback_id: Identifiers::MEMORY_CORRECT_MODAL, private_metadata: ModalState.encode(memory_post_id: @post.id, memory_id: @memory.id),
      values: {
        Slack::Modals::CorrectMemory::CORRECTION_BLOCK => { Slack::Modals::CorrectMemory::CORRECTION_INPUT => { "value" => correction } },
        Slack::Modals::CorrectMemory::REASON_BLOCK => { Slack::Modals::CorrectMemory::REASON_INPUT => { "value" => reason } }
      }
    )
  end

  def error_of(response) = response[:errors][Slack::Modals::CorrectMemory::CORRECTION_BLOCK]
end
