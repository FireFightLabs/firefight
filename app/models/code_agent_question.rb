# A question a coding agent asks while it writes a change: a choice between a few options, each with what it leads to, and
# the one the agent recommends with why. It is shown where the change was asked for, Halon answers it when what it already
# read settles it, and otherwise the person the change runs as picks an option or writes something else. One left
# unanswered past answer_due_at goes with the recommendation. A question asked before questions had options ends the
# change instead, since it has nothing to fall back on. Once settled, the person can change the answer while the change is
# still written, and the agent is sent the new one as a correction.
class CodeAgentQuestion < ApplicationRecord
  STATUS_OPEN = "open"
  STATUS_ANSWERED = "answered"
  STATUS_EXPIRED = "expired"
  # The change ended another way while the question waited.
  STATUS_WITHDRAWN = "withdrawn"
  # Nobody answered in time, so the change went with the recommended option.
  STATUS_DEFAULTED = "defaulted"
  STATUSES = [ STATUS_OPEN, STATUS_ANSWERED, STATUS_EXPIRED, STATUS_WITHDRAWN, STATUS_DEFAULTED ].freeze
  # Settled with an answer the change carries on with, so the person can still change it.
  CHANGEABLE = [ STATUS_ANSWERED, STATUS_DEFAULTED ].freeze

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
  belongs_to :changed_by, polymorphic: true, optional: true

  # The agent's words and the answer can quote the repository or a log, so both are kept like a chat's messages.
  encrypts :question, :answer, :recommended_reason, :changed_answer
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

  # A changed answer the agent has not been sent yet. correction_sent_for holds the changed_at of the last one it was sent.
  scope :correction_waiting, -> { where.not(changed_at: nil).where("correction_sent_for IS DISTINCT FROM changed_at") }

  def self.clean(text, limit) = Chat::SecretFree.redacted(text.to_s.squish).truncate(limit)

  def choices = Array(options).map { |option| Option.new(label: option["label"].to_s, consequence: option["consequence"].to_s) }

  def recommended_option = recommended && choices[recommended]

  # The option at index, or nil for anything that is not one of them.
  def choice_at(index) = (choices[index] if index.is_a?(Integer) && index >= 0)

  def chosen_option = chosen && choices[chosen]

  def open? = status == STATUS_OPEN

  def answered? = status == STATUS_ANSWERED

  def expired? = status == STATUS_EXPIRED

  def defaulted? = status == STATUS_DEFAULTED

  def overdue? = open? && answer_due_at <= Time.current

  # What happens when nobody answers in time, read after "If nobody answers by then,".
  def timeout_outcome = recommended_option ? "the change goes with the recommendation" : "the change stops"

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
    option = choice_at(index)
    option ? answer!(option.label, by: by, option: index) : false
  end

  # The person the change runs as changes a settled answer, Halon's, the clock's or their own, while the change is still
  # written, so the agent can still follow it. Never one still waiting, which is answered instead.
  def change_answer_blocked_reason(member)
    return "This question is still waiting for an answer, so answer it rather than change it." if open?
    return "The change this question was for has ended." unless CHANGEABLE.include?(status)
    return "The change this question was for has finished, so its answer can no longer change." unless session.running?
    return "Only #{session.principal&.actor_display_name || 'the person who asked for the change'} can change the answer, since the change runs as them." unless member && session.principal == member

    nil
  end

  def changeable? = CHANGEABLE.include?(status) && session.running?

  def changed? = changed_at.present?

  # What the change carries on with now: the option picked, by its index, or nil for an answer in someone's own words.
  def current_chosen = changed? ? changed_chosen : chosen

  def current_option = current_chosen && choices[current_chosen]

  # The answer the change carries on with now, in words: the option's label or someone's own words.
  def current_answer = current_option&.label || (changed? ? changed_answer : answer)

  def changed_by_name = changed_by&.actor_display_name

  # The new answer as the card and the thread show it, the option's label or the person's words.
  def changed_to = (changed_answer if changed?)

  # Whether this answer is the one the change already carries on with.
  def same_answer?(text, option)
    return option == current_chosen if option

    current_option.nil? && text.to_s.strip.casecmp?(current_answer.to_s)
  end

  # One guarded update, from a settled answer nobody changed since this was read, on a change still being written, so two
  # changes at once leave one standing and none lands once the change finished. option is the index of the option picked,
  # nil for the person's own words.
  def change_answer!(text, by:, option: nil)
    words = option ? choice_at(option)&.label : Chat::SecretFree.redacted(text.to_s.strip).truncate(ANSWER_LIMIT)
    return false if words.blank?

    moved = self.class.where(id: id, status: CHANGEABLE, changed_at: changed_at).where(code_agent_session_id: CodeAgentSession.running.select(:id))
                .update_all(changed_answer: words, changed_chosen: option, changed_by_type: by.class.polymorphic_name, changed_by_id: by.id,
                            changed_at: Time.current, updated_at: Time.current) == 1
    reload if moved
    moved
  end

  # The questions whose changed answer the agent was not sent yet, each claimed once against the change it read, so one
  # changed again meanwhile waits for the agent's next call rather than being lost.
  def self.claim_corrections!(session)
    correction_waiting.where(session: session).order(:created_at, :id).to_a
                      .select { |question| where(id: question.id, changed_at: question.changed_at).update_all(correction_sent_for: question.changed_at) == 1 }
  end

  # Once its change ends, a settled question's message in the thread is drawn again without Change answer.
  def self.changes_closed!(session)
    where(session: session, status: CHANGEABLE).where.not(message_id: nil).pluck(:id).each do |id|
      CodeAgentQuestionJob.perform_later(id, CodeAgentQuestionJob::SETTLED)
    end
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
    return changed_words if changed? && CHANGEABLE.include?(status)
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

  def changed_words
    option = changed_chosen && choices[changed_chosen]
    return "#{changed_by_name} chose: #{option.label}. #{option.consequence}" if option

    "#{changed_by_name} answered: #{changed_answer}"
  end

  # Sent to the agent with its next call once the person changed a settled answer, worded so it replaces the earlier one.
  def correction_words
    "The person changed their answer to your question \"#{question}\". This replaces the earlier answer. #{changed_words} " \
      "Follow this answer from now on, and undo anything you did only because of the earlier one."
  end

  # The shape a step's progress carries, Chat::CodeFixProgress#to_h.
  def to_h
    { "id" => id, "text" => question, "askedAt" => created_at&.utc&.iso8601, "answerDueAt" => answer_due_at&.utc&.iso8601,
      "status" => status, "answer" => answer, "answeredBy" => answered_by_name, "byHalon" => by_halon?,
      "answeredAt" => answered_at&.utc&.iso8601, "options" => choices.map(&:to_h), "recommended" => recommended,
      "recommendedReason" => recommended_reason, "chosen" => chosen, "timeoutOutcome" => timeout_outcome, "changedTo" => changed_to,
      "changedBy" => changed_by_name, "changedAt" => changed_at&.utc&.iso8601(6), "changedChosen" => (changed_chosen if changed?),
      "updatedAt" => updated_at&.utc&.iso8601(6) }
  end
end
