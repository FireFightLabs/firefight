# Every message posted is remembered on the approval so the decision, and how the call went once it ran, can be
# reflected in place. Workspaces without a channel still resolve approvals from the dashboard.
class ApprovalNotificationService
  # What a request says, as people read it: who wants to, what they want to do in plain words, how the approved call went
  # (OUTCOME_*), with its reason when it failed and the page it made when it did one.
  # rows are what a counted database write touches, as the asker's card would have shown them, and caution its warning
  # about text read from outside before the call.
  Shown = Data.define(:who, :action, :outcome, :reason, :link, :rows, :caution) do
    def initialize(rows: [], caution: nil, **) = super
  end
  HALON = "Halon".freeze
  OUTCOME_WORKING = :working
  OUTCOME_DONE = :done
  OUTCOME_FAILED = :failed

  def self.post!(approval)
    adapter = WorkspaceAdapter.for(approval.workspace)
    shown = shown(approval)
    channel_id = approval.request_channel_id
    asked = (approval.notify_dm? ? approval.human_approvers : []) | approval.on_call_to_ask
    # Nobody working the incident can decide, so whoever is on call for it is asked directly too.
    reached = asked.count { |member| ask_directly(approval, member, adapter, shown) }
    # A chat's request on Default is asked of its approvers, and in the channel only when no direct message reached
    # anyone, whether nobody could be messaged or Slack refused every one.
    in_channel = channel_id && (approval.notify_channel? || (approval.chat_default? && reached.zero?))
    deliver(approval) { adapter.post_approval_request(approval: approval, channel_id: channel_id, shown: shown) } if in_channel
    # Asked nowhere, so it waits on the Approvals page alone.
    return unless asked.empty? && !in_channel

    Rails.logger.warn({ event: "approval.nowhere_to_ask", approval_id: approval.id }.to_json)
  end

  # Someone just escalated to is on call for the incident from now on, so each request waiting there that they may
  # decide as whoever is on call reaches them too, by the same rule as when it was made, and never twice.
  def self.ask_on_call!(incident, member)
    adapter = WorkspaceAdapter.for(incident.workspace)
    incident.workspace.ability_approvals.pending.where(incident_id: incident.id, on_call_may_approve: true).find_each do |approval|
      ask_directly(approval, member, adapter, shown(approval)) if approval.on_call_to_ask.include?(member)
    end
  end

  # Each member is asked directly once per request, whichever way they came to be asked. A message Slack refused gives
  # the claim back, so a later ask can reach them. Returns whether they were reached.
  def self.ask_directly(approval, member, adapter, shown)
    return false if member.platform_user_id.blank? || !approval.claim_ask!(member)
    return true if deliver(approval) { adapter.post_approval_request_to_user(approval: approval, user_id: member.platform_user_id, shown: shown) }

    approval.release_ask!(member)
    false
  end
  private_class_method :ask_directly

  # Redraws every message the request was asked in, with the decision and, once the call ran, how it went.
  def self.mark_resolved!(approval)
    adapter = WorkspaceAdapter.for(approval.workspace)
    shown = shown(approval)
    approval.notifications.each do |notification|
      adapter.mark_approval_resolved(
        approval: approval, channel_id: notification["channel_id"], message_id: notification["message_id"], shown: shown
      )
    rescue AdapterError => e
      Rails.logger.warn({ event: "approval.resolution_update_failed", approval_id: approval.id, error: e.class.name }.to_json)
    end
  end

  def self.shown(approval)
    held = (Chat::HeldCall.find_by(id: approval.resume_payload.to_h["held_call_id"]) if approval.resume_payload.to_h["kind"] == Chat::HeldCall::RESUME_KIND)
    held_shown = held && Conversation::HeldCalls.shown(held)
    outcome, reason = outcome_of(approval)
    # A chat's call keeps why it failed in plain words, where the ledger keeps only the first line.
    reason = held.result.presence || reason if held && outcome == OUTCOME_FAILED
    Shown.new(who: approval.from_chat? ? HALON : approval.principal_name, action: held_shown&.action || action_words(approval),
              outcome: outcome, reason: reason, link: held_shown&.link, rows: held_shown&.rows || [], caution: held_shown&.caution)
  end

  # The call by what it does, such as "use api request on Faylee (Northflank)" or "delete incidents", never its key.
  def self.action_words(approval)
    key = approval.action_key
    return "use #{key.split('.', 2).last.tr('_.', '  ').downcase} on #{approval.connection_name}" if approval.connection_name

    "#{key.split('.').last.humanize(capitalize: false)} #{Ability::Action.label(Ability::Action.resource_of(key)).downcase}"
  end

  # How the call it approved went (Ability::Approval#run), in the words a request shows. Nothing until it runs.
  def self.outcome_of(approval)
    run = approval.run
    return [ nil, nil ] unless run
    return [ OUTCOME_WORKING, nil ] unless run.finished?
    return [ OUTCOME_DONE, nil ] if run.succeeded?

    [ OUTCOME_FAILED, run.error_summary ]
  end

  # Whether the message went out.
  def self.deliver(approval)
    result = yield
    approval.add_notification!(channel_id: result[:channel_id], message_id: result[:message_id])
    true
  rescue AdapterError => e
    Rails.logger.warn({ event: "approval.notification_failed", approval_id: approval.id, error: e.class.name }.to_json)
    false
  end
  private_class_method :deliver
end
