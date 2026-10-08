# A question a coding agent asks while it writes a change. It is shown where the change was asked for, Halon answers it
# when what it already read settles it, and otherwise the person the change runs as does. One left unanswered past
# answer_due_at ends the change with the question shown, since a guess would be worse than no change.
class CodeAgentQuestion < ApplicationRecord
  STATUS_OPEN = "open"
  STATUS_ANSWERED = "answered"
  STATUS_EXPIRED = "expired"
  # The change ended another way while the question waited.
  STATUS_WITHDRAWN = "withdrawn"
  STATUSES = [ STATUS_OPEN, STATUS_ANSWERED, STATUS_EXPIRED, STATUS_WITHDRAWN ].freeze

  ANSWER_WITHIN = 5.minutes
  # A change that needs more than this is a person's to write.
  MAX_PER_CHANGE = 2
  QUESTION_LIMIT = 1_000
  ANSWER_LIMIT = 2_000
  HALON = "Halon".freeze

  belongs_to :session, class_name: "CodeAgentSession", foreign_key: :code_agent_session_id, inverse_of: :questions
  belongs_to :workspace
  belongs_to :answered_by, polymorphic: true, optional: true

  # The agent's words and the answer can quote the repository or a log, so both are kept like a chat's messages.
  encrypts :question, :answer

  validates :status, inclusion: { in: STATUSES }
  validates :question, presence: true

  class Refused < StandardError; end

  # A second question waits for the first, and a change asks only a few, so the agent is told plainly when it cannot ask.
  def self.ask!(session, text)
    words = Chat::SecretFree.redacted(text.to_s.strip).truncate(QUESTION_LIMIT)
    raise Refused, "Ask a question in words." if words.blank?
    raise Refused, "Your earlier question is still waiting for an answer. Call wait_for_answer." if session.open_question
    raise Refused, "This change has asked its #{MAX_PER_CHANGE} questions. Work from what you have, and say in your summary what you assumed." if session.questions.count >= MAX_PER_CHANGE

    create!(session: session, workspace: session.workspace, question: words, answer_due_at: ANSWER_WITHIN.from_now)
  end

  def open? = status == STATUS_OPEN

  def answered? = status == STATUS_ANSWERED

  def expired? = status == STATUS_EXPIRED

  def overdue? = open? && answer_due_at <= Time.current

  def by_halon? = answered_by.is_a?(SystemAgent)

  def answered_by_name = by_halon? ? HALON : answered_by&.actor_display_name

  # The person the change runs as answers. Anyone else is told who can, and Halon answers through answer_as_halon!.
  def answer_blocked_reason(member)
    return "This question was already answered." if answered?
    return "Nobody answered this question in time, so the change stopped." if expired?
    return "The change this question was for has ended." unless open?
    return "Only #{session.principal&.actor_display_name || 'the person who asked for the change'} can answer, since the change runs as them." unless member && session.principal == member

    nil
  end

  # One guarded update from open, so two answers at once, or an answer as it expires, leave exactly one standing.
  def answer!(text, by:)
    words = Chat::SecretFree.redacted(text.to_s.strip).truncate(ANSWER_LIMIT)
    return false if words.blank?

    moved = self.class.where(id: id, status: STATUS_OPEN).where("answer_due_at > ?", Time.current)
                .update_all(status: STATUS_ANSWERED, answer: words, answered_by_type: by.class.polymorphic_name,
                            answered_by_id: by.id, answered_at: Time.current, updated_at: Time.current) == 1
    reload if moved
    moved
  end

  def answer_as_halon!(text) = answer!(text, by: SystemAgent.investigator)

  # Expires a question past its time, once, so whichever of the agent's wait and the change's watch sees it first wins.
  def expire_if_overdue!
    return false unless overdue?

    moved = self.class.where(id: id, status: STATUS_OPEN).where(answer_due_at: ..Time.current)
                .update_all(status: STATUS_EXPIRED, updated_at: Time.current) == 1
    return false unless moved

    reload
    CodeAgentQuestionJob.perform_later(id, CodeAgentQuestionJob::SETTLED)
    true
  end

  def self.withdraw_open!(session)
    where(session: session, status: STATUS_OPEN).pluck(:id).each do |id|
      next unless where(id: id, status: STATUS_OPEN).update_all(status: STATUS_WITHDRAWN, updated_at: Time.current) == 1

      CodeAgentQuestionJob.perform_later(id, CodeAgentQuestionJob::SETTLED)
    end
  end

  # What the agent is told it may do next, once the question settled.
  def agent_words
    return "#{answered_by_name} answered: #{answer}" if answered?
    return "Nobody answered within #{ANSWER_WITHIN.in_minutes.to_i} minutes. Stop now, change nothing more, and end with your question in your summary." if expired?

    "This change has ended."
  end

  # The shape a step's progress carries, Chat::CodeFixProgress#to_h.
  def to_h
    { "id" => id, "text" => question, "askedAt" => created_at&.utc&.iso8601, "answerDueAt" => answer_due_at&.utc&.iso8601,
      "status" => status, "answer" => answer, "answeredBy" => answered_by_name, "byHalon" => by_halon?,
      "answeredAt" => answered_at&.utc&.iso8601 }
  end
end
