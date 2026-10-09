# A question a coding agent asks while it writes a change: a choice between a few options, each with what it leads to, and
# the one the agent recommends with why. It is shown where the change was asked for, Halon answers it when what it already
# read settles it, and otherwise the person the change runs as picks an option or writes something else. One left
# unanswered past answer_due_at goes with the recommendation. A question asked before questions had options ends the
# change instead, since it has nothing to fall back on.
class CodeAgentQuestion < ApplicationRecord
  STATUS_OPEN = "open"
  STATUS_ANSWERED = "answered"
  STATUS_EXPIRED = "expired"
  # The change ended another way while the question waited.
  STATUS_WITHDRAWN = "withdrawn"
  # Nobody answered in time, so the change went with the recommended option.
  STATUS_DEFAULTED = "defaulted"
  STATUSES = [ STATUS_OPEN, STATUS_ANSWERED, STATUS_EXPIRED, STATUS_WITHDRAWN, STATUS_DEFAULTED ].freeze

  ANSWER_WITHIN = 5.minutes
  # A change that needs more than this is a person's to write.
  MAX_PER_CHANGE = 2
  QUESTION_LIMIT = 1_000
  ANSWER_LIMIT = 2_000
  HALON = "Halon".freeze
  MIN_OPTIONS = 2
  MAX_OPTIONS = 4
  LABEL_LIMIT = 80
  CONSEQUENCE_LIMIT = 240
  REASON_LIMIT = 300

  # label is what the choice is called, consequence what choosing it leads to, in a line.
  Option = Data.define(:label, :consequence) do
    def to_h = { "label" => label, "consequence" => consequence }
  end

  belongs_to :session, class_name: "CodeAgentSession", foreign_key: :code_agent_session_id, inverse_of: :questions
  belongs_to :workspace
  belongs_to :answered_by, polymorphic: true, optional: true

  # The agent's words and the answer can quote the repository or a log, so both are kept like a chat's messages.
  encrypts :question, :answer, :recommended_reason
  serialize :options, coder: JSON
  encrypts :options

  validates :status, inclusion: { in: STATUSES }
  validates :question, presence: true

  class Refused < StandardError; end

  WAITING = "Your earlier question is still waiting for an answer. Call wait_for_answer.".freeze

  # A second question waits for the first, and a change asks only a few, so the agent is told plainly when it cannot ask.
  # options are hashes with a label and a consequence, recommended the label of the one it recommends. The agent can ask
  # twice at once, so the cap is claimed in SQL and the database keeps a second open question out.
  def self.ask!(session, text, options:, recommended:, reason:)
    words = clean(text, QUESTION_LIMIT)
    raise Refused, "Ask a question in words." if words.blank?
    raise Refused, WAITING if session.open_question

    given = Array(options).map { |option| option.to_h.transform_keys(&:to_s) }
              .map { |option| Option.new(label: clean(option["label"], LABEL_LIMIT), consequence: clean(option["consequence"], CONSEQUENCE_LIMIT)) }
    unless given.size.between?(MIN_OPTIONS, MAX_OPTIONS) && given.all? { |option| option.label.present? && option.consequence.present? }
      raise Refused, "Give #{MIN_OPTIONS} to #{MAX_OPTIONS} options, each with a short label and a one-line consequence."
    end

    pick = given.index { |option| option.label.casecmp?(clean(recommended, LABEL_LIMIT)) }
    raise Refused, "Name the option you recommend by its label, as one of the options you gave." unless pick
    raise Refused, "Say in a sentence why you recommend it." if reason.to_s.strip.blank?
    raise Refused, "This change has asked its #{MAX_PER_CHANGE} questions. Work from what you have, and say in your summary what you assumed." unless session.count_question!

    begin
      transaction(requires_new: true) do
        create!(session: session, workspace: session.workspace, question: words, options: given.map(&:to_h), recommended: pick,
                recommended_reason: clean(reason, REASON_LIMIT), answer_due_at: ANSWER_WITHIN.from_now)
      end
    rescue ActiveRecord::RecordNotUnique
      session.uncount_question!
      raise Refused, WAITING
    end
  end

  def self.clean(text, limit) = Chat::SecretFree.redacted(text.to_s.squish).truncate(limit)

  def choices = Array(options).map { |option| Option.new(label: option["label"].to_s, consequence: option["consequence"].to_s) }

  def recommended_option = recommended && choices[recommended]

  def chosen_option = chosen && choices[chosen]

  def open? = status == STATUS_OPEN

  def answered? = status == STATUS_ANSWERED

  def expired? = status == STATUS_EXPIRED

  def defaulted? = status == STATUS_DEFAULTED

  def overdue? = open? && answer_due_at <= Time.current

  def by_halon? = answered_by.is_a?(SystemAgent)

  def answered_by_name = by_halon? ? HALON : answered_by&.actor_display_name

  # The person the change runs as answers. Anyone else is told who can, and Halon answers through answer_as_halon!.
  def answer_blocked_reason(member)
    return "This question was already answered." if answered?
    return "Nobody answered this question in time, so the change stopped." if expired?
    return "Nobody answered this question in time, so the change went with the recommendation." if defaulted?
    return "The change this question was for has ended." unless open?
    return "Only #{session.principal&.actor_display_name || 'the person who asked for the change'} can answer, since the change runs as them." unless member && session.principal == member

    nil
  end

  # One guarded update from open, so two answers at once, or an answer as it expires, leave exactly one standing. option is
  # the index of the option picked, nil for an answer in the person's own words.
  def answer!(text, by:, option: nil)
    words = Chat::SecretFree.redacted(text.to_s.strip).truncate(ANSWER_LIMIT)
    return false if words.blank?

    moved = self.class.where(id: id, status: STATUS_OPEN).where("answer_due_at > ?", Time.current)
                .update_all(status: STATUS_ANSWERED, answer: words, chosen: option,
                            answered_by_type: by.class.polymorphic_name, answered_by_id: by.id, answered_at: Time.current, updated_at: Time.current) == 1
    reload if moved
    moved
  end

  # One of the options, by its index, answered with its label.
  def choose!(index, by:)
    option = index.is_a?(Integer) && index >= 0 ? choices[index] : nil
    option ? answer!(option.label, by: by, option: index) : false
  end

  def answer_as_halon!(text, option: nil) = answer!(text, by: SystemAgent.investigator, option: option)

  # Settles a question past its time, once, so whichever of the agent's wait and the change's watch sees it first wins:
  # with the recommended option when it has one, otherwise as expired.
  def expire_if_overdue!
    return false unless overdue?

    settled = recommended_option ? { status: STATUS_DEFAULTED, chosen: recommended } : { status: STATUS_EXPIRED }
    moved = self.class.where(id: id, status: STATUS_OPEN).where(answer_due_at: ..Time.current)
                .update_all(**settled, updated_at: Time.current) == 1
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
    return chosen_words if answered? && chosen_option
    return "#{answered_by_name} answered: #{answer}" if answered?
    if defaulted?
      return "Nobody answered within #{ANSWER_WITHIN.in_minutes.to_i} minutes, so go with your recommendation: #{recommended_option.label}. " \
             "#{recommended_option.consequence} Say in your summary that it was not answered and what you went with."
    end

    return "Nobody answered within #{ANSWER_WITHIN.in_minutes.to_i} minutes. Stop now, change nothing more, and end with your question in your summary." if expired?

    "This change has ended."
  end

  def chosen_words
    why = (" #{answer}" unless answer == chosen_option.label)
    "#{answered_by_name} chose: #{chosen_option.label}. #{chosen_option.consequence}#{why}"
  end

  # The shape a step's progress carries, Chat::CodeFixProgress#to_h.
  def to_h
    { "id" => id, "text" => question, "askedAt" => created_at&.utc&.iso8601, "answerDueAt" => answer_due_at&.utc&.iso8601,
      "status" => status, "answer" => answer, "answeredBy" => answered_by_name, "byHalon" => by_halon?,
      "answeredAt" => answered_at&.utc&.iso8601, "options" => choices.map(&:to_h), "recommended" => recommended,
      "recommendedReason" => recommended_reason, "chosen" => chosen }
  end
end
