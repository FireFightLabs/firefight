# What a run's Ask a person step asked, or the task a Manual step gave: the question or the task, the choices it offers
# or the short form it asks people to fill, who was asked, and the answer that carries the step on. A task is done
# once, by the person it was given to, or by anyone when it was given to anyone. Answered once, in one statement, so two
# people answering at the same moment cannot both win. A question nobody answered in time, or whose run stopped
# waiting, is expired.
class Workflow::Run::Question < ApplicationRecord
  self.table_name = "workflow_run_questions"

  STATUS_OPEN = "open".freeze
  STATUS_ANSWERED = "answered".freeze
  STATUS_EXPIRED = "expired".freeze
  STATUSES = [ STATUS_OPEN, STATUS_ANSWERED, STATUS_EXPIRED ].freeze

  # An Ask a person step's question, or a Manual step's task.
  KIND_QUESTION = "question".freeze
  KIND_TASK = "task".freeze
  KINDS = [ KIND_QUESTION, KIND_TASK ].freeze

  # Each choice: the key its route is named by, and the words on its button.
  CHOICE_KEY = "key".freeze
  CHOICE_LABEL = "label".freeze
  # Each of a short form's fields: the name later steps read it by, and what the person is asked.
  FIELD_NAME = "name".freeze
  FIELD_LABEL = "label".freeze
  ANSWER_CHOICE = "choice".freeze
  ANSWER_FIELDS = "fields".freeze
  ANSWER_LIMIT = 2_000
  CHOICE_LIMIT = 5
  FIELD_LIMIT = 5

  belongs_to :workspace
  belongs_to :run_step, class_name: "Workflow::Run::Step"
  belongs_to :answered_by, class_name: "WorkspaceMembership", optional: true

  validates :question, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: KINDS }

  delegate :run, to: :run_step

  scope :open, -> { where(status: STATUS_OPEN) }

  def open? = status == STATUS_OPEN
  def answered? = status == STATUS_ANSWERED
  def expired? = status == STATUS_EXPIRED
  def task? = kind == KIND_TASK

  def form? = fields.any?

  def asked_members = workspace.workspace_memberships.where(id: asked_member_ids)

  def choice_keys = choices.map { |choice| choice[CHOICE_KEY] }

  # Who may answer: everyone it was asked of, any member for a task given to anyone, and in a test run the person testing.
  def answerer?(member)
    return false unless member
    return true if open_to_anyone? && member.workspace_id == workspace_id

    asked_member_ids.include?(member.id) || (run.test? && run.started_by_id == member.id)
  end

  # Why this member cannot answer it now, or nil when they can.
  def answer_blocked_reason(member)
    return "#{answered_by&.actor_display_name || 'Someone'} already #{task? ? 'did this' : 'answered this'}." if answered?
    return "This #{task? ? 'task' : 'question'} is no longer asked." if expired? || due_at <= Time.current || !waiting?
    return "Only #{asked_words} can #{task? ? 'mark this done' : 'answer this'}." unless answerer?(member)

    nil
  end

  # What is wrong with an answer, or nil. It needs one of the choices when there are any, and every field of the form filled.
  def answer_problem(choice, values)
    return "Pick one of the choices." if choices.any? && !choice_keys.include?(choice.to_s)
    return "This question offers no choices." if choices.empty? && choice.present?
    return "Answer #{fields.map { |field| field[FIELD_LABEL] }.first}." if form? && fields.any? { |field| values.to_h[field[FIELD_NAME]].to_s.strip.empty? }
    return "Keep each answer to #{ANSWER_LIMIT.to_fs(:delimited)} characters." if values.to_h.values.any? { |value| value.to_s.length > ANSWER_LIMIT }

    nil
  end

  # Settles it with the answer, only while it is open and before its time is up. Answers whether this answer won.
  def answer!(by:, choice:, values:)
    kept = fields.to_h { |field| [ field[FIELD_NAME], values.to_h[field[FIELD_NAME]].to_s.strip ] }
    answer = { ANSWER_CHOICE => choice.presence, ANSWER_FIELDS => kept }
    now = Time.current
    won = self.class.where(id: id, status: STATUS_OPEN).where("due_at > ?", now)
                    .update_all(status: STATUS_ANSWERED, answer: answer, answered_by_id: by.id, answered_at: now, updated_at: now) == 1
    reload
    won
  end

  # Only from open, in one statement, so an answer given at the same moment stands.
  def expire!
    now = Time.current
    moved = self.class.where(id: id, status: STATUS_OPEN).update_all(status: STATUS_EXPIRED, updated_at: now) == 1
    reload
    moved
  end

  # Keeps where it was sent, only while it is open, so a settlement's redraw reaches it. False when it was settled
  # meanwhile, and the caller redraws that message itself. A post in a channel names no member.
  def add_notification!(channel_id:, message_id:, member_id:)
    entry = [ { "channel_id" => channel_id, "message_id" => message_id, "member_id" => member_id } ].to_json
    kept = self.class.where(id: id, status: STATUS_OPEN)
                     .update_all([ "notifications = notifications || ?::jsonb, updated_at = ?", entry, Time.current ]) == 1
    reload
    kept
  end

  # Whether it was posted in its channel already, so it is never posted there twice.
  def posted_in_channel? = notifications.any? { |notification| notification["member_id"].nil? }

  # The step is still parked for it.
  def waiting? = run_step.reload.status == Workflow::Run::Step::STATUS_WAITING

  # The words on a choice's button, the builder's label.
  def choice_words(key) = choices.find { |choice| choice[CHOICE_KEY] == key.to_s }&.dig(CHOICE_LABEL) || key.to_s.humanize

  # Who it was asked of, as a sentence, or anyone for a task given to anyone.
  def asked_words
    return "anyone in the workspace" if open_to_anyone?

    asked_members.map(&:actor_display_name).to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
  end

  def answer_words
    return unless answered?

    chosen = answer.to_h[ANSWER_CHOICE]
    filled = fields.filter_map do |field|
      value = answer.to_h.dig(ANSWER_FIELDS, field[FIELD_NAME])
      "#{field[FIELD_LABEL]}: #{value}" if value.present?
    end
    [ (choice_words(chosen) if chosen), *filled ].compact.join("\n")
  end
end
