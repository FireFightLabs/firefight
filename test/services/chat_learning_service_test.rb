require "test_helper"

class ChatLearningServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @conversation.ask!("Where does web deploy from?")
    @conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "The deploy settings of web name the release branch.")
    Entitlements.stubs(:allows?).returns(true)
    FirefightAi::MemoryJudge.any_instance.stubs(:verdicts).returns([])
  end

  test "a quiet chat is read once for lasting facts, each saved through learn! as the investigator, unconfirmed and from a chat with its person" do
    lessons([ "web deploys from the release branch", nil ], [ "Checkout currently runs 3 replicas", nil ])
    FirefightAi::ChatLessons.any_instance.expects(:extract).with { |transcript:, remembered:|
      transcript == "#{@member.display_name}: Where does web deploy from?\nHalon: The deploy settings of web name the release branch." && remembered.empty?
    }.returns(@lessons)

    saved = ChatLearningService.new(@conversation).learn!

    memory = saved.sole
    assert_equal [ "web deploys from the release branch", Chat::Memory::STATE_UNCONFIRMED, @conversation, @member, nil ],
                 memory.values_at(:text, :state).push(memory.source, memory.added_by, memory.confirmed_by)
    assert_equal Chat::MemoryEvent::KIND_LEARNED, memory.events.sole.kind
    assert @conversation.reload.learned_through_at
    entries = @workspace.ability_invocations.where(action_key: "memory.create", principal: SystemAgent.investigator).order(:created_at)
    assert_equal 2, entries.count, "a lesson memory never holds is refused after it is allowed, as for remember"
    entry = entries.first
    assert_equal [ AbilityGateway::SOURCE_CONVERSATION, { "conversation" => @conversation.id } ], [ entry.source, entry.params ]

    FirefightAi::ChatLessons.any_instance.expects(:extract).never
    assert_empty ChatLearningService.new(@conversation.reload).learn!, "nothing was said since"
  end

  test "what Halon already remembered in the chat is handed over as known and never learned a second time" do
    Chat::Tools::Remember.new(Conversation::Turn.new(@conversation, asker: @member)).call("fact" => "web deploys from the release branch")
    lessons([ "Web deploys from the release branch.", nil ])
    FirefightAi::ChatLessons.any_instance.expects(:extract).with { |remembered:, **| remembered.map(&:text) == [ "web deploys from the release branch" ] }.returns(@lessons)

    assert_empty ChatLearningService.new(@conversation).learn!
    assert_equal 1, Chat::Memory.where(workspace: @workspace, source: @conversation).count
  end

  test "only what was said since the last read is read, and a model that cannot answer leaves the chat for next time" do
    @conversation.update_columns(learned_through_at: 1.second.from_now)
    travel 1.minute
    @conversation.ask!("And the worker?")
    FirefightAi::ChatLessons.any_instance.expects(:extract).with { |transcript:, **| transcript == "#{@member.display_name}: And the worker?" }
                            .raises(FirefightAi::TerminalError.new("out of credit", reason: "OutOfCredit"))
    read_before = @conversation.reload.learned_through_at

    assert_empty ChatLearningService.new(@conversation).learn!
    assert_equal read_before, @conversation.reload.learned_through_at
  end

  test "a name the chat gave is looked up as the chat's person sees the map and catalog, and a name nothing has is about the whole workspace" do
    lessons([ "Auth Service keeps sessions in Redis", "Auth Service" ], [ "The worker restarts nightly", "nowhere" ])
    FirefightAi::ChatLessons.any_instance.stubs(:extract).returns(@lessons)

    saved = ChatLearningService.new(@conversation).learn!

    assert_equal [ catalog_entries(:auth_service), nil ], saved.map(&:subject)
  end

  test "a chat is read once quiet, never while something was said since or an answer is being written, and at once when archived" do
    FirefightAi::ChatLessons.any_instance.stubs(:extract).returns([])
    ChatLearningService.any_instance.expects(:learn!).twice
    @conversation.update_columns(answer_owed_since: nil)

    ConversationLearningJob.perform_now(@conversation.id, 1.second.from_now)
    ConversationLearningJob.perform_now(@conversation.id, 1.hour.ago)
    @conversation.update_columns(answer_owed_since: Time.current)
    ConversationLearningJob.perform_now(@conversation.id, 1.second.from_now)
    @conversation.update_columns(answer_owed_since: nil)
    ConversationLearningJob.perform_now(@conversation.id)
  end

  test "archiving a chat, however it is archived, has Halon read it at once, and restoring it does not" do
    assert_enqueued_with(job: ConversationLearningJob, args: [ @conversation.id ]) { @conversation.archive!(true) }
    assert_no_enqueued_jobs(only: ConversationLearningJob) { @conversation.archive!(false) }
  end

  test "a chat about an incident tells its channel what it learned, as remember does, and one about nothing tells nobody" do
    lessons([ "web deploys from the release branch", nil ])
    FirefightAi::ChatLessons.any_instance.stubs(:extract).returns(@lessons)
    assert_no_enqueued_jobs(only: MemoryNoteJob) { ChatLearningService.new(@conversation).learn! }

    incident = incidents(:active_critical_ws1)
    chat = Conversation.start_personal!(workspace: @workspace, member: @member)
    chat.update!(subject: incident)
    chat.ask!("Where does checkout deploy from?")
    lessons([ "Checkout deploys from main", nil ])
    FirefightAi::ChatLessons.any_instance.stubs(:extract).returns(@lessons)

    assert_enqueued_with(job: MemoryNoteJob, args: ->(args) { args[1] == Chat::MemoryPost::KIND_LEARNED && args[2] == chat }) do
      ChatLearningService.new(chat).learn!
    end
  end

  test "every turn queues a read for when the chat goes quiet" do
    Conversation::Runner.any_instance.stubs(:run)

    assert_enqueued_with(job: ConversationLearningJob, args: ->(args) { args.first == @conversation.id }) do
      ConversationReplyJob.perform_now(@conversation.id, @member.id)
    end
  end

  private

  def lessons(*facts)
    @lessons = facts.map { |fact, about| FirefightAi::ChatLessons::Lesson.new(fact: fact, about: about, confidence: 0.9) }
  end
end
