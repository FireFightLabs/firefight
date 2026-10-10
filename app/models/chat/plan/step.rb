# One step of a plan Halon keeps in a chat. A read looks something up, a change changes something and carries how to put
# it back, written before it runs, and a check reads whether the changes worked.
class Chat::Plan::Step < ApplicationRecord
  include Chat::SecretFree

  self.table_name = "chat_plan_steps"

  KIND_READ = "read"
  KIND_CHANGE = "change"
  KIND_CHECK = "check"
  KINDS = [ KIND_READ, KIND_CHANGE, KIND_CHECK ].freeze

  STATUS_NOT_STARTED = "not_started"
  STATUS_RUNNING = "running"
  STATUS_DONE = "done"
  STATUS_FAILED = "failed"
  STATUS_SKIPPED = "skipped"
  STATUSES = [ STATUS_NOT_STARTED, STATUS_RUNNING, STATUS_DONE, STATUS_FAILED, STATUS_SKIPPED ].freeze
  ENDED = [ STATUS_DONE, STATUS_FAILED, STATUS_SKIPPED ].freeze

  # What a check found against what the changes were meant to do.
  VERDICT_HELD = "held"
  VERDICT_NOT_HELD = "not_held"
  VERDICT_UNKNOWN = "could_not_check"
  VERDICTS = [ VERDICT_HELD, VERDICT_NOT_HELD, VERDICT_UNKNOWN ].freeze

  DESCRIPTION_LIMIT = 300
  NOTE_LIMIT = 1_000
  LINKS_LIMIT = 5

  belongs_to :plan, class_name: "Chat::Plan", inverse_of: :steps

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :verdict, inclusion: { in: VERDICTS }, allow_nil: true
  validates :description, presence: true

  # A step as Halon asked for it, checked and not saved yet. Raises Chat::Plan::Refused with why.
  def self.checked(asked, position:, scheduled:)
    refuse = ->(why) { raise Chat::Plan::Refused, "Step #{position} #{why}." }
    refuse.call("must be an object") unless asked.is_a?(Hash)

    asked = asked.stringify_keys
    kind = asked["kind"].to_s
    refuse.call("is a #{kind.inspect}, which is not one of #{KINDS.join(', ')}") unless KINDS.include?(kind)

    step = new(position: position, kind: kind, description: asked["description"].to_s.squish.truncate(DESCRIPTION_LIMIT),
               place: asked["place"].to_s.squish.presence, tool: asked["tool"].to_s.strip.presence, undo: asked["undo"].to_s.strip.presence)
    refuse.call("has no description. Say in a few words what it does") if step.description.blank?
    if step.change?
      refuse.call("changes something and has no undo. Write how to put it back before it runs") if step.undo.blank?
      refuse.call("changes something on a schedule and names no tool. Name the tool it calls, so the person approves exactly that") if scheduled && step.tool.blank?
    end
    refuse.call("holds what looks like a secret. Never put a credential in a plan") unless step.valid? || step.errors[:text].empty?
    step
  end

  def read? = kind == KIND_READ
  def change? = kind == KIND_CHANGE
  def check? = kind == KIND_CHECK

  def not_started? = status == STATUS_NOT_STARTED
  def running? = status == STATUS_RUNNING
  def done? = status == STATUS_DONE
  def failed? = status == STATUS_FAILED
  def ended? = ENDED.include?(status)

  def held? = verdict == VERDICT_HELD

  # Why this step cannot move to status now, or nil. A failed step may run again, which is what Retry is.
  def move_blocked_reason(status, verdict: nil)
    return "#{status.inspect} is not one of #{(STATUSES - [ STATUS_NOT_STARTED ]).join(', ')}." unless STATUSES.include?(status) && status != STATUS_NOT_STARTED
    return "Step #{position} already ended as #{words}. Only a failed step runs again." if ended? && !(failed? && status == STATUS_RUNNING)
    return "Step #{position} changes something and has no undo. Give its undo before it runs." if change? && undo.blank?
    if check? && status == STATUS_DONE && !VERDICTS.include?(verdict.to_s)
      return "A check that is done says whether the changes worked, as verdict, one of #{VERDICTS.join(', ')}."
    end

    nil
  end

  def words = status.tr("_", " ")

  def text = [ description, place, undo, note ].compact.join(" ")
end
