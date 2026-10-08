# A code change that reached its spending limit before it finished. It is a pause, not a failure: the work so far is
# committed and kept on a branch of its own, and the person the change runs as decides with Continue or Stop. Continue
# gives it another budget of the same size and carries on where it stopped, in the same box and the same agent session
# while the box is still there, otherwise from the saved branch with a handover. Stop deletes the saved branch.
class CodeAgentSession::Pause < ApplicationRecord
  STATUS_OFFERED = "offered"
  # Continue was pressed and the change is running again.
  STATUS_CONTINUING = "continuing"
  STATUS_STOPPED = "stopped"
  STATUSES = [ STATUS_OFFERED, STATUS_CONTINUING, STATUS_STOPPED ].freeze

  # How long the box and the agent's own session are kept for Continue to carry on in place. A conversation's box
  # closes this long after its last read (CodeBox::IDLE_AFTER), so the pause marks it used and waits no longer.
  RESUMABLE_FOR = CodeBox::IDLE_AFTER

  QUESTION = "This fix has reached its spending limit before finishing. Continue?".freeze
  # The argument a code host's code change tool is called with when the person pressed Continue, naming the pause. A
  # model setting it gets nowhere, since only a pause someone continued is carried on.
  CONTINUE_ARG = "continue_paused".freeze

  belongs_to :session, class_name: "CodeAgentSession", inverse_of: :pauses
  belongs_to :workspace
  belongs_to :conversation, optional: true
  belongs_to :decided_by, class_name: "WorkspaceMembership", optional: true

  # What the change was asked with can quote evidence, so it is kept like a chat's messages.
  serialize :arguments, coder: JSON
  encrypts :arguments

  validates :status, inclusion: { in: STATUSES }

  def offered? = status == STATUS_OFFERED

  def continuing? = status == STATUS_CONTINUING

  def stopped? = status == STATUS_STOPPED

  # Whether Continue can still carry on in the box and the agent session it stopped in.
  def resumable_in_place? = agent_session_id.present? && resumable_until.future? && box_key.present? && CodeBox.live.exists?(key: box_key)

  # Continue and Stop run as whoever asked for the change, so only they decide.
  def decide_blocked_reason(member)
    return "This was already decided." unless offered?
    return "Only #{session.principal.try(:display_name) || 'the person who asked'} can decide, since the change runs as them." unless member && session.principal == member

    nil
  end

  # Continue or Stop pressed, once. False when someone decided first.
  def decide!(member, to:)
    moved = self.class.where(id: id, status: STATUS_OFFERED)
                .update_all(status: to, decided_by_id: member.id, decided_at: Time.current, updated_at: Time.current) == 1
    reload
    moved
  end

  # The shape the step's progress carries, Chat::CodeFixProgress#to_h.
  def to_h
    { "id" => id, "status" => status, "question" => QUESTION, "savedBranch" => saved_branch, "decidedBy" => decided_by&.display_name,
      "resumableUntil" => resumable_until&.utc&.iso8601 }
  end
end
