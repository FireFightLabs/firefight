# What a run's Ask a person step asked: the question, the choices it offers or the short form it asks people to fill,
# who was asked, and the answer that carries the step on. Answered once, in one statement, so two people answering at
# the same moment cannot both win. A question nobody answered in time, or whose run stopped waiting, is expired.
class Workflow::Run::Question < ApplicationRecord
  self.table_name = "workflow_run_questions"

  STATUS_OPEN = "open".freeze
  STATUS_ANSWERED = "answered".freeze
  STATUS_EXPIRED = "expired".freeze
  STATUSES = [ STATUS_OPEN, STATUS_ANSWERED, STATUS_EXPIRED ].freeze

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

  delegate :run, to: :run_step

  scope :open, -> { where(status: STATUS_OPEN) }

  def open? = status == STATUS_OPEN
  def answered? = status == STATUS_ANSWERED
  def expired? = status == STATUS_EXPIRED

  def form? = fields.any?

  def asked_members = workspace.workspace_memberships.where(id: asked_member_ids)

  # Who may answer: everyone it was asked of, and in a test run the person testing too.
  def answerer?(member)
    return false unless member

    asked_member_ids.include?(member.id) || (run.test? && run.started_by_id == member.id)
  end

  # Why this member cannot answer it now, or nil when they can.
  def answer_blocked_reason(member)
    return "#{answered_by&.actor_display_name || 'Someone'} already answered this." if answered?
    return "This question is no longer asked." if expired? || !waiting?
    return "Only #{asked_members.map(&:actor_display_name).to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')} can answer this." unless answerer?(member)

    nil
  end

  # What is wrong with an answer, or nil. It needs one of the choices when there are any, and every field of the form filled.
  def answer_problem(choice, values)
    return "Pick one of the choices." if choices.any? && !choices.include?(choice.to_s)
    return "This question offers no choices." if choices.empty? && choice.present?
    return "Answer #{fields.map { |field| field[FIELD_LABEL] }.first}." if form? && fields.any? { |field| values.to_h[field[FIELD_NAME]].to_s.strip.empty? }
    return "Keep each answer to #{ANSWER_LIMIT.to_fs(:delimited)} characters." if values.to_h.values.any? { |value| value.to_s.length > ANSWER_LIMIT }

    nil
  end

  # Settles it with the answer, only while it is open. Answers whether this answer won.
  def answer!(by:, choice:, values:)
    kept = fields.to_h { |field| [ field[FIELD_NAME], values.to_h[field[FIELD_NAME]].to_s.strip ] }
    answer = { ANSWER_CHOICE => choice.presence, ANSWER_FIELDS => kept }
    now = Time.current
    won = self.class.where(id: id, status: STATUS_OPEN)
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

  def add_notification!(channel_id:, message_id:, member_id:)
    entry = [ { "channel_id" => channel_id, "message_id" => message_id, "member_id" => member_id } ].to_json
    self.class.where(id: id).update_all([ "notifications = notifications || ?::jsonb, updated_at = ?", entry, Time.current ])
    reload
  end

  # The step is still parked for it.
  def waiting? = run_step.reload.status == Workflow::Run::Step::STATUS_WAITING

  def choice_words(choice) = choice.to_s.humanize

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
