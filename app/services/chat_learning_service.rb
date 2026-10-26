# What a chat with Halon taught about the setup, written down once the chat goes quiet or is archived, so the next chat or
# run starts from it. A quick model reads what was said since Halon last read the chat (FirefightAi::ChatLessons), and
# each lesson goes through Chat::Memory.learn!, so it is screened, never saved twice in any words, never learned again
# once rejected, and disputes what it contradicts. What Halon already remembered in the chat is handed over as known, so
# nothing is learned twice. Saved as the investigator through the gateway, so an admin who revokes its memory grant stops
# it and each save is in Activity.
class ChatLearningService
  # How much of what the workspace already holds the model reads, the most recently changed first.
  REMEMBERED_LIMIT = 60

  def initialize(conversation)
    @conversation = conversation
    @workspace = conversation.workspace
  end

  # Returns the memories it saved. Nothing new said since the last read, or a workspace whose plan does not include AI,
  # saves nothing. A model that cannot answer, such as when the account is out of credit, leaves the chat to be read
  # next time it goes quiet.
  def learn!
    return [] unless learns?

    messages = unread
    return [] if messages.none? { |message| message.role == Chat::Message::ROLE_USER }

    lessons = FirefightAi::ChatLessons.new(@workspace, inferable: @conversation, member: member).extract(transcript: transcript(messages), remembered: remembered)
    saved = lessons.filter_map { |lesson| save(lesson) }
    read_through!(messages.last.created_at)
    saved
  rescue FirefightAi::Error => error
    Rails.logger.info({ event: "chat_learning.failed", conversation_id: @conversation.id, error: error.class.name }.to_json)
    []
  end

  private

  def learns?
    defined?(FirefightAi) && Entitlements.allows?(@workspace, Entitlements::AI) && @conversation.chat.present?
  end

  # What the person and Halon said since the chat was last read for lessons.
  def unread
    scope = @conversation.chat.readable_messages.where(notice: false)
    scope = scope.where(created_at: (@conversation.learned_through_at + 0.000001)..) if @conversation.learned_through_at
    scope.to_a.select { |message| message.content.is_a?(String) && message.content.present? }
  end

  def transcript(messages)
    messages.map { |message| "#{message.role == Chat::Message::ROLE_USER ? speaker(message) : 'Halon'}: #{message.content}" }.join("\n")
  end

  # Who wrote it, as the chat names them, or the person the chat is with.
  def speaker(message)
    (message.sender_id && @conversation.chat.sender_name(message)) || member&.display_name || "Person"
  end

  # What this chat already saved, and what the workspace holds about what it is about and the whole workspace, rejected
  # ones marked, so the model never writes any of it again.
  def remembered
    subjects = Chat::Memory.subjects_for(@conversation.incident)
    scope = Chat::Memory.where(workspace: @workspace).where.not(state: Chat::Memory::STATE_MERGED)
    about = subjects.group_by { |subject| subject.class.name }.map { |type, found| scope.where(subject_type: type, subject_id: found.map(&:id)) }
    held = about.inject(scope.where(subject_id: nil).or(scope.where(source: @conversation))) { |union, part| union.or(part) }
    held.order(updated_at: :desc).limit(REMEMBERED_LIMIT).map do |memory|
      FirefightAi::ChatLessons::Remembered.new(text: memory.text, rejected: memory.state == Chat::Memory::STATE_REJECTED)
    end
  end

  def save(lesson)
    # Halon already remembered it in this chat, so it is not learned a second time.
    return nil if said_here.include?(Chat::Memory::Words.signature(lesson.fact))

    Chat::Memory.changed_by_halon(@workspace, Ability::Action::ACTION_CREATE, params: { "conversation" => @conversation.id }, chat: @conversation) do
      learned = Chat::Memory.learn!(@workspace, text: lesson.fact, subject: subject(lesson.about), source: @conversation, added_by: member,
                                                judge: judge, contradiction: "A chat showed \"#{lesson.fact}\".")
      learned.memory if learned.outcome == Chat::Memory::LEARNED_SAVED
    end
  rescue ActiveRecord::RecordInvalid
    # One holding a secret is dropped rather than failing the others.
    nil
  end

  # The name the model gave, as the chat's own reader may see it. A name nothing has, or several share, saves the fact for
  # the whole workspace, as resolve does.
  def subject(name)
    Chat::Memory.subject_named(@workspace, name, principal: reader).subject
  end

  def said_here
    @said_here ||= Chat::Memory.where(workspace: @workspace, source: @conversation).map { |memory| Chat::Memory::Words.signature(memory.text) }.to_set
  end

  def judge = @judge ||= FirefightAi::MemoryJudge.new(@workspace, inferable: @conversation, member: member)

  # Whoever the chat was with, when a member, as a chat names who taught a memory. A chat in an issue acts as the agent.
  def member
    @conversation.started_by if @conversation.started_by.is_a?(WorkspaceMembership) && !@conversation.issue?
  end

  def reader = @conversation.turn_asker(nil) || SystemAgent.investigator

  def read_through!(at)
    Conversation.where(id: @conversation.id).update_all([ "learned_through_at = GREATEST(learned_through_at, ?)", at ])
  end
end
