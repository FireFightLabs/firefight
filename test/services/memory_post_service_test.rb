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

  test "a reminder posted before Halon checked memories itself still takes a decision, redrawn in the direct message it landed in" do
    bob = workspace_memberships(:bob_workspace_one)
    taught = Chat::Memory.create!(workspace: @workspace, text: "Checkout reads from the replica", state: Chat::Memory::STATE_UNCONFIRMED, added_by: bob)
    post = Chat::MemoryPost.create!(workspace: @workspace, kind: Chat::MemoryPost::KIND_REMINDER, recipient: bob, channel_id: "D42", message_id: "7.1",
                                    memory_ids: [ taught.id ])
    @adapter.expects(:update_learned_memories).with { |channel_id:, message_id:, post:|
      channel_id == "D42" && message_id == "7.1" && post.reminder == MemoryPostService::ShownReminder.new(taught: 1, learned: 0, direct: true)
    }

    MemoryPostService.new(@workspace).decide!(reference: post.id, memory_id: taught.id, member: bob, confirmed: false, channel_id: "D42", message_id: "7.1")

    assert_equal "Marked not right in a reminder", taught.reload.state_reason
  end

  test "Halon no longer sends reminders" do
    assert_not_respond_to MemoryPostService.new(@workspace), :remind!
  end

  test "the person who confirmed a memory Halon found evidence against is told once by direct message, with Still right, Not right and Edit" do
    @memory.confirm!(by: @member)
    @memory.dispute!("Halon checked it against production and found otherwise.")
    @adapter.expects(:post_learned_memories_to_user).with { |user_id:, post:|
      user_id == @member.platform_user_id && post.kind == Chat::MemoryPost::KIND_CHALLENGED && post.memories.map(&:id) == [ @memory.id ]
    }.returns(message_id: "9.1", channel_id: "D9")

    MemoryChallengeJob.perform_now(@memory.id)

    post = Chat::MemoryPost.find_by!(kind: Chat::MemoryPost::KIND_CHALLENGED, recipient: @member)
    assert_equal [ "D9", "9.1", "a direct message" ], [ post.channel_id, post.message_id, post.place ]
    buttons = Slack::Messages::LearnedMemories.build(MemoryPostService.new(@workspace).shown(post))
                                              .select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements].map { |button| button.dig(:text, :text) } }
    assert_equal [ "Still right", "Not right", "Edit" ], buttons
  end

  test "a second job for the same dispute sends nothing, and a new dispute with new words is sent" do
    @memory.confirm!(by: @member)
    @memory.dispute!("Halon found the settings name release.")
    @adapter.expects(:post_learned_memories_to_user).twice.returns(message_id: "9.1", channel_id: "D9")

    2.times { MemoryChallengeJob.perform_now(@memory.id) }
    @memory.update_columns(state_reason: nil)
    @memory.update!(state_reason: "Halon found the last deploys came from the hotfix branch.")
    MemoryChallengeJob.perform_now(@memory.id)

    assert_equal 2, Chat::MemoryPost.where(kind: Chat::MemoryPost::KIND_CHALLENGED).count
  end

  test "a passing platform error is raised for the job to try again, and a person who left or can no longer see it is not told" do
    @memory.confirm!(by: @member)
    @memory.dispute!("Found otherwise.")
    @adapter.stubs(:post_learned_memories_to_user).raises(AdapterError::RateLimited.new("slow down"))
    assert_raises(AdapterError::RateLimited) { MemoryPostService.new(@workspace).tell_people_behind!(@memory.reload) }
    assert_not Chat::MemoryPost.exists?(kind: Chat::MemoryPost::KIND_CHALLENGED)

    @adapter.expects(:post_learned_memories_to_user).never
    @member.update_columns(removed_at: Time.current)
    assert_empty MemoryPostService.new(@workspace).tell_people_behind!(@memory.reload)
  end

  test "nobody is messaged when the memory is no longer disputed, the person has no platform account, or the platform refuses" do
    @adapter.expects(:post_learned_memories_to_user).never
    @memory.confirm!(by: @member)
    assert_empty MemoryPostService.new(@workspace).tell_people_behind!(@memory)

    @adapter.unstub(:post_learned_memories_to_user)
    @memory.dispute!("Found otherwise.")
    @adapter.stubs(:post_learned_memories_to_user).raises(AdapterError::NotFound)
    assert_empty MemoryPostService.new(@workspace).tell_people_behind!(@memory.reload)
    assert_not Chat::MemoryPost.exists?(kind: Chat::MemoryPost::KIND_CHALLENGED)
  end

  test "the person who approved a lesson Halon found evidence against is told once by direct message, as a lesson they approved" do
    lesson = Chat::Memory.create!(workspace: @workspace, text: "Checkout retries go up when the payment timeout changes", state: Chat::Memory::STATE_UNCONFIRMED,
                                  source: @incident)
    assert lesson.approve!(by: @member)
    lesson.dispute!("Halon checked it against production and found otherwise.")
    @adapter.expects(:post_learned_memories_to_user).with { |user_id:, post:|
      user_id == @member.platform_user_id && post.kind == Chat::MemoryPost::KIND_CHALLENGED && post.memories.map(&:id) == [ lesson.id ]
    }.once.returns(message_id: "9.1", channel_id: "D9")

    2.times { MemoryChallengeJob.perform_now(lesson.id) }

    post = Chat::MemoryPost.find_by!(kind: Chat::MemoryPost::KIND_CHALLENGED, recipient: @member)
    shown = MemoryPostService.new(@workspace).shown(post)
    assert shown.approved_lesson
    assert_equal "Halon found evidence against a lesson you approved", Slack::Messages::LearnedMemories.plain_title(shown)
    blocks = Slack::Messages::LearnedMemories.build(shown)
    assert_equal "Halon and pull request reviews stopped using it until you decide. Keep it if it is still right, mark it not right, or edit it.",
                 blocks.last[:elements].sole[:text]
  end

  test "when one person confirmed a lesson and another approved it, each is told once, the confirmer as before" do
    bob = workspace_memberships(:bob_workspace_one)
    lesson = Chat::Memory.create!(workspace: @workspace, text: "Checkout retries go up when the payment timeout changes", state: Chat::Memory::STATE_UNCONFIRMED,
                                  source: @incident)
    assert lesson.approve!(by: @member)
    lesson.confirm!(by: bob)
    lesson.dispute!("Halon checked it against production and found otherwise.")
    @adapter.expects(:post_learned_memories_to_user).twice.returns(message_id: "9.1", channel_id: "D9")

    2.times { MemoryChallengeJob.perform_now(lesson.id) }

    service = MemoryPostService.new(@workspace)
    to_bob = Chat::MemoryPost.find_by!(kind: Chat::MemoryPost::KIND_CHALLENGED, recipient: bob)
    to_approver = Chat::MemoryPost.find_by!(kind: Chat::MemoryPost::KIND_CHALLENGED, recipient: @member)
    assert_equal "Halon found evidence against a memory you confirmed", Slack::Messages::LearnedMemories.plain_title(service.shown(to_bob))
    assert_equal "Halon found evidence against a lesson you approved", Slack::Messages::LearnedMemories.plain_title(service.shown(to_approver))
  end

  test "Edit in a message about evidence against an approved lesson keeps it approved, strict as it was, when the editor may decide on lessons" do
    lesson = challenged_lesson(strict: true)
    post = Chat::MemoryPost.create!(workspace: @workspace, kind: Chat::MemoryPost::KIND_CHALLENGED, recipient: @member, channel_id: "D9", memory_ids: [ lesson.id ])

    assert_nil MemoryPostService.new(@workspace).correct!(post_id: post.id, memory_id: lesson.id, member: @member,
                                                          correction: "Checkout retries go up when the payment timeout drops", reason: nil)

    replacement = lesson.reload.replaced_by
    assert_equal Chat::Memory::STATE_REJECTED, lesson.state
    assert_equal [ "Checkout retries go up when the payment timeout drops", @member, true, Chat::Memory::Lesson::STATUS_APPROVED ],
                 [ replacement.text, replacement.approved_by, replacement.strict, replacement.lesson_status ]
    entry = @workspace.ability_invocations.find_by!(action_key: Ability::Action::LESSON_DECIDE, principal: @member)
    assert_equal AbilityGateway::SOURCE_SLACK, entry.source
  end

  test "Edit by someone who may not decide on lessons corrects it as before, without approving the new words" do
    bob = workspace_memberships(:bob_workspace_one)
    lesson = challenged_lesson
    post = Chat::MemoryPost.create!(workspace: @workspace, kind: Chat::MemoryPost::KIND_CHALLENGED, recipient: bob, channel_id: "D8", memory_ids: [ lesson.id ])

    assert_nil MemoryPostService.new(@workspace).correct!(post_id: post.id, memory_id: lesson.id, member: bob,
                                                          correction: "Checkout retries go up when the payment timeout drops", reason: "It moved")

    replacement = lesson.reload.replaced_by
    assert_equal [ "It moved", bob, nil ], [ lesson.state_reason, replacement.confirmed_by, replacement.approved_by ]
    assert_equal Chat::Memory::Lesson::STATUS_WAITING, replacement.lesson_status
  end

  test "a channel message says who approved a lesson the way it says who confirmed one, whatever Halon's check made of it" do
    lesson = challenged_lesson
    lesson.confirm!(by: @member)
    lesson.update_columns(confirmed_by_id: nil, decided_by_halon: true)
    unchecked = Chat::Memory.create!(workspace: @workspace, text: "Checkout keeps sessions in Redis", state: Chat::Memory::STATE_UNCONFIRMED, source: @incident)
    assert unchecked.approve!(by: @member)
    post = Chat::MemoryPost.create!(workspace: @workspace, incident: @incident, kind: Chat::MemoryPost::KIND_INCIDENT, channel_id: @incident.channel_id,
                                    memory_ids: [ lesson.id, unchecked.id ])

    said = context_text(MemoryPostService.new(@workspace).shown(post))

    assert_equal 2, said.scan(":white_check_mark: Approved by #{@member.display_name} for pull request reviews").size
    assert_not_includes said, "Checked by Halon"
  end

  test "Edit in an incident channel message keeps an approved lesson approved when the editor may decide on lessons" do
    lesson = challenged_lesson(strict: true)
    lesson.confirm!(by: @member)
    post = Chat::MemoryPost.create!(workspace: @workspace, incident: @incident, kind: Chat::MemoryPost::KIND_INCIDENT, channel_id: @incident.channel_id,
                                    memory_ids: [ lesson.id ])

    assert_nil MemoryPostService.new(@workspace).correct!(post_id: post.id, memory_id: lesson.id, member: @member,
                                                          correction: "Checkout retries go up when the payment timeout drops", reason: nil)

    replacement = lesson.reload.replaced_by
    assert_equal [ @member, true, Chat::Memory::Lesson::STATUS_APPROVED ], [ replacement.approved_by, replacement.strict, replacement.lesson_status ]
  end

  test "Edit with the same words on a disputed approved lesson keeps it as still right, whoever edits it" do
    bob = workspace_memberships(:bob_workspace_one)
    lesson = challenged_lesson
    post = Chat::MemoryPost.create!(workspace: @workspace, kind: Chat::MemoryPost::KIND_CHALLENGED, recipient: bob, channel_id: "D8", memory_ids: [ lesson.id ])

    assert_nil MemoryPostService.new(@workspace).correct!(post_id: post.id, memory_id: lesson.id, member: bob, correction: lesson.text, reason: nil)

    assert_equal [ Chat::Memory::STATE_CONFIRMED, bob, nil, Chat::Memory::Lesson::STATUS_APPROVED ],
                 [ lesson.reload.state, lesson.confirmed_by, lesson.replaced_by_id, lesson.lesson_status ]
  end

  private

  def context_text(shown)
    Slack::Messages::LearnedMemories.build(shown).flat_map { |block| Array(block[:elements]).filter_map { |element| element[:text] if element.is_a?(Hash) && block[:type] == "context" } }.join(" ")
  end

  def challenged_lesson(strict: false)
    lesson = Chat::Memory.create!(workspace: @workspace, text: "Checkout retries go up when the payment timeout changes", state: Chat::Memory::STATE_UNCONFIRMED,
                                  source: @incident)
    assert lesson.approve!(by: @member, strict: strict)
    lesson.dispute!("Halon checked it against production and found otherwise.")
    lesson
  end
end
