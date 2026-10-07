# A call Halon made in a chat that an approval rule held for someone else to approve. Approving it never runs it. Once
# approved, Halon reads how things stand now, and the person who asked runs it from the chat, or dismisses it. An approval
# nobody runs within Ability::Approval::RUN_WINDOW expires and can be asked for again.
class Chat::HeldCall < ApplicationRecord
  # The approval's resume_payload kind, which is how a decision on the approval finds this call.
  RESUME_KIND = "chat_call".freeze

  STATUS_WAITING = "waiting"
  STATUS_CHECKING = "checking"
  STATUS_READY = "ready"
  STATUS_RUNNING = "running"
  STATUS_RAN = "ran"
  STATUS_FAILED = "failed"
  STATUS_DISMISSED = "dismissed"
  STATUS_EXPIRED = "expired"
  STATUS_DENIED = "denied"
  # Expired, and asked for again, which is a new held call.
  STATUS_ASKED_AGAIN = "asked_again"
  STATUSES = [
    STATUS_WAITING, STATUS_CHECKING, STATUS_READY, STATUS_RUNNING, STATUS_RAN, STATUS_FAILED, STATUS_DISMISSED, STATUS_EXPIRED,
    STATUS_DENIED, STATUS_ASKED_AGAIN
  ].freeze
  # Approved and not yet run, dismissed or expired.
  OPEN = [ STATUS_CHECKING, STATUS_READY ].freeze
  # How it ended, which Halon is told once, at its next turn. A run is told as it happens when the chat allows it.
  TOLD = [ STATUS_RAN, STATUS_FAILED, STATUS_DISMISSED, STATUS_EXPIRED, STATUS_DENIED ].freeze
  RESULT_LIMIT = 2_000

  belongs_to :chat
  belongs_to :approval, class_name: "Ability::Approval"
  belongs_to :decided_by, class_name: "WorkspaceMembership", optional: true
  # Halon's reading of how things stand now, on a chat of its own.
  has_one :check, class_name: "Chat", as: :owner, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :state_change, inclusion: { in: Chat::CurrentState::CHANGES }, allow_nil: true

  scope :untold, -> { where(status: TOLD, told_at: nil) }

  # Keeps the call with its chat and points the approval at it, so approving or denying it reaches this chat.
  def self.hold!(chat:, approval:, tool_name:, tool_call_id:, target:)
    transaction do
      held = create!(chat: chat, approval: approval, tool_name: tool_name.to_s, tool_call_id: tool_call_id, target: target)
      approval.update!(held_for_run: true, resume_payload: { kind: RESUME_KIND, held_call_id: held.id })
      held
    end
  end

  def conversation = chat.owner

  def workspace = chat.workspace

  def workspace_id = chat.workspace_id

  # Whoever asked, since the approval is bound to them and the call runs as them whoever presses Run.
  def asker = approval.principal

  def expires_at = approval.run_expires_at

  def asker_name = asker.try(:display_name) || approval.principal_label

  # What it shows now, an approved call whose window passed reading as expired before the job marks it.
  def shown_status = lapsed? ? STATUS_EXPIRED : status

  # What may be done with it in this state, whoever does it. Run shows while Halon checks, blocked with why.
  def offers
    case shown_status
    when STATUS_CHECKING, STATUS_READY then [ Chat::CurrentState::ACTION_RUN, Chat::CurrentState::ACTION_DISMISS ]
    when STATUS_EXPIRED then [ Chat::CurrentState::ACTION_ASK_AGAIN ]
    else []
    end
  end

  # Approved and still open, past its window, before the job that marks it has run.
  def lapsed? = OPEN.include?(status) && approval.run_lapsed?

  def waiting? = status == STATUS_WAITING
  def checking? = status == STATUS_CHECKING
  def ready? = status == STATUS_READY
  def expired? = status == STATUS_EXPIRED || lapsed?

  # Moves only from where it was, so a double click or two workers never act twice. False when it had moved.
  def move!(from:, to:, **columns)
    moved = self.class.where(id: id, status: Array(from)).update_all(status: to, updated_at: Time.current, **columns)
    reload
    moved == 1
  end

  # What Halon read can quote what a provider said, so anything that looks like a credential is replaced first.
  def checked!(report)
    move!(from: STATUS_CHECKING, to: STATUS_READY, checked_state: report.state && Chat::SecretFree.redacted(report.state), state_change: report.change,
          state_checked_at: report.checked_at)
  end

  def claim_run!(by:)
    move!(from: STATUS_READY, to: STATUS_RUNNING, decided_by_id: by.id, decided_at: Time.current)
  end

  def finish!(ok:, result:, invocation_id: nil)
    move!(from: STATUS_RUNNING, to: ok ? STATUS_RAN : STATUS_FAILED, result: result.to_s.truncate(RESULT_LIMIT).presence, invocation_id: invocation_id)
  end

  # Why this person cannot run it now, or nil. Whoever asked may, and so may someone in the chat who may make the same
  # call themselves. It still runs as whoever asked, since that is who it was approved for.
  # How the run went, read from its ledger row, which the gateway wrote with this approval. A call refused before it ran
  # has no allowed row, and failed. A failure keeps the first line of why. What a call that went through answered is
  # Halon's to tell, in the chat.
  def ran!(said)
    invocation = Ability::Invocation.where(approval_id: approval_id, decision: Ability::Invocation::DECISION_ALLOW).order(:created_at).last
    ok = invocation&.outcome == Ability::Invocation::OUTCOME_SUCCESS
    finish!(ok: ok, result: (invocation&.error_summary || Ability::Invocation.summary_of(said) unless ok), invocation_id: invocation&.id)
  end

  ASKED_AGAIN = :asked_again
  NO_RULE_NOW = :no_rule_now
  NOT_ALLOWED = :not_allowed

  # Asks the approvers again for exactly the same call, as whoever asked it, and keeps the new request with the chat.
  # Nothing runs here, since the gateway is asked only for an approval.
  def ask_again!
    renewed = AbilityGateway.request_approval!(
      principal: asker, action_key: approval.action_key, workspace: workspace, scope: approval.scope, params: approval.params,
      context: { source: AbilityGateway::SOURCE_CONVERSATION, incident_id: conversation.try(:incident_id) }.compact
    )
    renewed.nil? ? NO_RULE_NOW : ASKED_AGAIN
  rescue AbilityGateway::PendingApproval => pending
    approval.lapse_run!
    transaction do
      self.class.hold!(chat: chat, approval: pending.approval, tool_name: tool_name, tool_call_id: tool_call_id, target: target)
      move!(from: [ STATUS_EXPIRED, *OPEN ], to: STATUS_ASKED_AGAIN)
    end
    ASKED_AGAIN
  rescue AbilityGateway::Denied
    NOT_ALLOWED
  end

  def run_blocked_reason(member)
    return "Halon is still checking how things stand now." if checking?
    return expired_reason if expired?
    return "This is no longer waiting to be run." unless ready?
    return "Only #{asker_name} or someone who may make this call can run it." unless may_run?(member)

    nil
  end

  def dismiss_blocked_reason(member)
    return "This is no longer waiting to be run." unless OPEN.include?(status) && !lapsed?
    return "Only #{asker_name} or someone who may make this call can dismiss it." unless may_run?(member)

    nil
  end

  def ask_again_blocked_reason(member)
    return "Only an approval that expired can be asked for again." unless expired?
    return "Only #{asker_name} can ask for this again." unless approval.requester?(member)

    nil
  end

  def may_run?(member)
    return false unless member
    return true if approval.requester?(member)

    action = Ability::Action.lookup(approval.action_key, workspace)
    AbilityGateway.permitted?(member, action, approval.action_key, workspace, approval.scope)
  end

  EXPIRED = "The approval expired before anyone ran it. Ask for it again if it is still needed.".freeze

  def expired_reason = EXPIRED
end
