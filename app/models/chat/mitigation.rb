# A change Halon made in a chat that customers feel for a while, such as a feature flag turned off or a service scaled
# down (Ability::Action::EFFECT_MITIGATION). It is undone after the time the person chose when they confirmed it,
# DEFAULT_MINUTES unless they changed it, with a reminder REMIND_BEFORE that, unless someone keeps it. Its undo is
# written once it ran, from what the call returned (Conversation::Mitigations). Every move is one guarded update, so
# two workers never remind or undo twice.
class Chat::Mitigation < ApplicationRecord
  STATUS_PROPOSED = "proposed"
  STATUS_ACTIVE = "active"
  STATUS_KEPT = "kept"
  STATUS_UNDOING = "undoing"
  STATUS_UNDONE = "undone"
  STATUS_UNDO_FAILED = "undo_failed"
  STATUS_UNDO_HELD = "undo_held"
  STATUS_DUE_BY_HAND = "due_by_hand"
  STATUS_CANCELLED = "cancelled"
  # Ran as a step of a plan whose Undo was pressed, so the plan's undo puts it back and Firefight never undoes it again.
  STATUS_WITH_PLAN = "with_plan"
  STATUSES = [
    STATUS_PROPOSED, STATUS_ACTIVE, STATUS_KEPT, STATUS_UNDOING, STATUS_UNDONE, STATUS_UNDO_FAILED, STATUS_UNDO_HELD, STATUS_DUE_BY_HAND,
    STATUS_CANCELLED, STATUS_WITH_PLAN
  ].freeze
  # How it ended, which Halon hears once at its next turn.
  TOLD = [ STATUS_KEPT, STATUS_UNDONE, STATUS_UNDO_FAILED, STATUS_UNDO_HELD, STATUS_DUE_BY_HAND ].freeze
  # Shown in the chat, from the moment it ran.
  SHOWN = STATUSES - [ STATUS_PROPOSED, STATUS_CANCELLED ]

  UNDO_NONE = "none"
  UNDO_WRITING = "writing"
  UNDO_READY = "ready"
  # Halon could not write an undo it can run itself, so a person does it, with undo_note saying what.
  UNDO_BY_HAND = "by_hand"
  UNDO_STATES = [ UNDO_NONE, UNDO_WRITING, UNDO_READY, UNDO_BY_HAND ].freeze

  DEFAULT_MINUTES = 60
  # What the person may choose when they confirm it, in minutes. Keeping it is nil.
  DURATIONS = [ 15, 60, 240, 1_440 ].freeze
  REMIND_BEFORE = 15.minutes
  # Extend adds this to the time left.
  EXTEND_BY = 60.minutes
  # A claim not let go of in this long belonged to a worker that died.
  CLAIM_LAPSES = 15.minutes
  RESULT_LIMIT = 2_000

  belongs_to :chat
  belongs_to :workspace
  belongs_to :asker, polymorphic: true, optional: true
  belongs_to :ended_by, class_name: "WorkspaceMembership", optional: true
  # The plan step it ran as, when Halon made it while carrying out a plan, so it and the plan are undone once between them.
  belongs_to :plan_step, class_name: "Chat::Plan::Step", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :undo_state, inclusion: { in: UNDO_STATES }
  validates :duration_minutes, inclusion: { in: DURATIONS }, allow_nil: true

  scope :shown, -> { where(status: SHOWN) }
  scope :untold, -> { where(status: TOLD, told_at: nil) }
  scope :remind_due, ->(now = Time.current) { where(status: STATUS_ACTIVE, reminded_at: nil).where(expires_at: ..(now + REMIND_BEFORE)) }
  scope :expiry_due, ->(now = Time.current) { where(status: STATUS_ACTIVE).where(expires_at: ..now) }

  # The steps of a plan whose changes Firefight already put back when their time ran out or someone pressed Undo now, so
  # the plan's own undo leaves them out.
  def self.undone_steps(plan) = where(plan_step_id: plan.steps.select(:id), status: STATUS_UNDONE).pluck(:plan_step_id).to_set

  def self.for_call(chat, tool_call_id) = chat && tool_call_id.present? ? find_by(chat: chat, tool_call_id: tool_call_id.to_s) : nil

  # A duration in minutes as a person reads it, such as "1 hour" or "4 hours".
  def self.duration_words(minutes)
    return "never" if minutes.nil?

    count, unit = (minutes % 60).zero? ? [ minutes / 60, "hour" ] : [ minutes, "minute" ]
    "#{count} #{unit.pluralize(count)}"
  end

  KEEP = "keep".freeze

  # nil keeps it. Anything not offered falls back to the default, so a crafted value cannot set a long one.
  def self.chosen_minutes(value)
    return nil if value.to_s == KEEP

    minutes = Integer(value.to_s, exception: false)
    DURATIONS.include?(minutes) ? minutes : DEFAULT_MINUTES
  end

  def conversation = chat.owner

  def active? = status == STATUS_ACTIVE

  def kept? = status == STATUS_KEPT

  def proposed? = status == STATUS_PROPOSED

  def ended? = !(proposed? || active? || status == STATUS_UNDOING)

  def asker_name = asker.try(:display_name) || "The person who asked"

  # Moves only from where it was, so a double click or two workers never act twice. False when it had moved.
  def move!(from:, to:, **columns)
    moved = self.class.where(id: id, status: Array(from)).update_all(status: to, updated_at: Time.current, **columns)
    reload
    moved == 1
  end

  # Ran, so its time starts now rather than when it was confirmed.
  # A change the person chose to keep is told to Halon as it runs, so it is never told again.
  def start!(result:)
    expires = duration_minutes && duration_minutes.minutes.from_now
    move!(from: STATUS_PROPOSED, to: duration_minutes ? STATUS_ACTIVE : STATUS_KEPT, started_at: Time.current, expires_at: expires,
          result: Chat::SecretFree.redacted(result.to_s).truncate(RESULT_LIMIT), undo_state: UNDO_WRITING, told_at: (Time.current unless duration_minutes))
  end

  # The reminder is claimed once, so two sweeps never send two.
  def claim_reminder! = self.class.where(id: id, status: STATUS_ACTIVE, reminded_at: nil).update_all(reminded_at: Time.current, updated_at: Time.current) == 1

  # Why this person may not keep, extend or undo it now, or nil. Whoever asked may, and in a chat in a channel or
  # thread anyone there may, since the asker may be away when it runs out. A personal dashboard chat is its owner's.
  def change_blocked_reason(member)
    return "This is no longer running, so there is nothing to change." unless active? || kept?
    return nil if member == asker || conversation.thread_id.present?

    "Only #{asker_name} can change this, since it was made in their own chat."
  end

  def undo_blocked_reason(member)
    blocked = change_blocked_reason(member)
    return blocked if blocked
    return "Halon is still writing how to undo this. Try again in a moment." if undo_state == UNDO_WRITING
    return "Halon could not write an undo it can run itself. #{undo_note}" if undo_state == UNDO_BY_HAND

    nil
  end

  def extend_blocked_reason(member)
    change_blocked_reason(member) || ("It is kept, so it is not undone at any time." if kept?)
  end

  def keep_blocked_reason(member)
    change_blocked_reason(member) || ("It is already kept." if kept?)
  end

  # What it changed, as a person reads it, in the agent's sentence or else as the call and what it reaches.
  def title = intent.presence&.delete_suffix(".") || label

  # The call and what it reaches, short enough for a toast, such as "Feature flag disable on Product (PostHog)".
  def label = [ call_words, (" on #{target}" if target.present?) ].join

  def call_words
    tool = workspace.connection_tools_by_name[tool_name.to_s]
    (tool ? tool.name : tool_name).to_s.tr("_.", "  ").humanize
  end
end
