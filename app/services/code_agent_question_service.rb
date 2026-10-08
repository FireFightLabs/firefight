# Where a coding agent's question is shown and answered. It is posted in the Slack thread of the chat or fix it was asked
# in, Halon answers it when what it already knows settles it, and otherwise the person the change runs as answers it from
# the dashboard or the thread. Every surface is redrawn once it settles.
class CodeAgentQuestionService
  Answered = Data.define(:ok, :words)

  ANSWERED = "Your answer was sent to the coding agent.".freeze
  EMPTY = "Write an answer first.".freeze

  # Shown in the thread first, so the person sees it while Halon reads what it knows.
  def self.asked!(question)
    post!(question)
    try_halon!(question)
  end

  GONE = "This question is gone.".freeze

  # The question a platform's button names, and why this member cannot answer it, or nil when they can.
  def self.for_answer(workspace, id, member)
    question = CodeAgentQuestion.find_by(id: id, workspace: workspace)
    question ? [ question, question.answer_blocked_reason(member) ] : [ nil, GONE ]
  end

  # The person's answer from a platform's form, which names the question by id.
  def self.answer_by_id!(workspace, id, text, by:)
    question = CodeAgentQuestion.find_by(id: id, workspace: workspace)
    question ? answer!(question, text, by: by) : Answered.new(ok: false, words: GONE)
  end

  # The person's answer. A refusal says why, in the words the guard gives.
  def self.answer!(question, text, by:)
    blocked = question.answer_blocked_reason(by)
    return Answered.new(ok: false, words: blocked) if blocked
    return Answered.new(ok: false, words: EMPTY) if text.to_s.strip.empty?
    return Answered.new(ok: false, words: question.reload.answer_blocked_reason(by) || EMPTY) unless question.answer!(text, by: by)

    redraw!(question)
    Answered.new(ok: true, words: ANSWERED)
  end

  # Halon answers only what the person's words and the evidence settle, and anything else waits for the person.
  def self.try_halon!(question)
    return unless question.open?

    answer = FirefightAi::QuestionAnswerer.new(question.workspace, inferable: question.session).answer(
      question: question.question, known: known(question.session.place)
    )
    redraw!(question) if answer && question.answer_as_halon!(answer)
  rescue FirefightAi::Error => error
    Rails.logger.warn({ event: "code_question.halon_did_not_answer", question_id: question.id, error: error.class.name }.to_json)
  end

  def self.post!(question)
    channel_id, thread_id = thread_of(question.session.place)
    return if channel_id.blank? || thread_id.blank? || question.message_id.present?

    posted = WorkspaceAdapter.for(question.workspace).post_code_question(channel_id: channel_id, thread_id: thread_id, question: question)
    question.update_columns(message_channel_id: posted[:channel_id], message_id: posted[:message_id])
  rescue AdapterError => error
    Rails.logger.warn({ event: "code_question.unposted", question_id: question.id, error: error.class.name }.to_json)
  end

  def self.redraw!(question)
    return if question.message_id.blank?

    WorkspaceAdapter.for(question.workspace).update_code_question(channel_id: question.message_channel_id, message_id: question.message_id,
                                                                  question: question)
  rescue AdapterError => error
    Rails.logger.warn({ event: "code_question.redraw_failed", question_id: question.id, error: error.class.name }.to_json)
  end

  CHAT_MESSAGES_KNOWN = 30

  # What Halon knows about the change where it was asked for: a chat as the person and Halon wrote it with what it read,
  # or a fix's finding, its evidence and what the run was asked.
  def self.known(place)
    case place
    when Conversation
      chat = place.chat
      return "" unless chat

      said = chat.readable_messages.last(CHAT_MESSAGES_KNOWN).map { |message| "#{message.role == Chat::Message::ROLE_USER ? 'The person' : 'Halon'}: #{message.content}" }
      read = CodeAgent::Request.kept_evidence(CodeAgent::ChatEvidence.for(chat, place.workspace)).map { |item| FirefightAi::Evidence.frame(item.label, item.text) }
      Chat::SecretFree.redacted([ *said, *read ].join("\n\n"))
    when Investigation::RemediationStep then place.code_question_material
    else ""
    end
  end
  private_class_method :known

  # A chat's own thread, or the thread of the run whose fix is being applied.
  def self.thread_of(place)
    case place
    when Conversation then [ place.channel_id, place.thread_id ]
    when Investigation::RemediationStep
      investigation = place.plan.finding.investigation
      [ investigation.channel_id, investigation.thread_id ]
    else [ nil, nil ]
    end
  end
  private_class_method :thread_of
end
