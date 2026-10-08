# A call an approval rule held in a chat, from its approval to its run. Approving it never runs it, it unlocks the
# call. Halon reads how things stand now, the person who asked is told where the chat lives, and nothing runs until someone
# presses Run. The run goes through the gateway again with the approval, once.
module Conversation::HeldCalls
  # What the card and the Slack message draw. call and target name the call as the confirmation does ("Api request" on
  # "Faylee (Northflank), project faylee"). offers is what may be done now, whoever does it.
  Shown = Data.define(
    :id, :conversation_id, :status, :headline, :call, :target, :asked, :state, :warning, :checked_at, :expires_at,
    :decided_by, :result, :offers
  )

  COULD_NOT_FINISH = "Firefight could not finish this call. Check whether it went through before asking for it again.".freeze

  NO_RULE_NOW = "No approval rule holds this call any more, so ask Halon to make it again.".freeze
  NOT_ALLOWED_NOW = "%<asker>s may no longer make this call, so it cannot be asked for again.".freeze

  # From ApprovalResumption once an approver approved. The call waits for its person and Halon reads how things stand.
  def self.approved!(approval)
    held = Chat::HeldCall.find_by(approval: approval)
    return unless held&.move!(from: Chat::HeldCall::STATUS_WAITING, to: Chat::HeldCall::STATUS_CHECKING)

    ApprovedCallExpiryJob.set(wait_until: approval.run_expires_at).perform_later(approval.id) if approval.run_expires_at
    HeldCallCheckJob.perform_later(held.id)
    tell!(held)
  end

  def self.denied!(approval)
    held = Chat::HeldCall.find_by(approval: approval)
    tell!(held) if held&.move!(from: Chat::HeldCall::STATUS_WAITING, to: Chat::HeldCall::STATUS_DENIED)
  end

  # From ApprovedCallExpiryJob, once the approval lapsed unused.
  def self.expired!(approval)
    held = Chat::HeldCall.find_by(approval: approval)
    tell!(held) if held&.move!(from: Chat::HeldCall::OPEN, to: Chat::HeldCall::STATUS_EXPIRED)
  end

  # Halon reads how things stand now, as the person who asked and only through reads. A check that cannot run or finds
  # nothing still makes the call ready, saying plainly that nobody checked.
  def self.check!(held)
    return unless held.checking?

    report = Chat::StateCheck.run(
      owner: held, workspace: held.workspace, principal: held.asker, source: AbilityGateway::SOURCE_CONVERSATION,
      call: Chat::StateCheck::Call.new(named: named(held), asked: asked(held), approved_by: approver_name(held.approval))
    )
    tell!(held) if held.checked!(report)
  end

  # Claims the call for this person and hands the run to the chat's next turn, which runs it and tells Halon what it
  # said. Returns why not, or nil.
  def self.run!(held, by:)
    blocked = held.run_blocked_reason(by)
    return blocked if blocked
    return held.reload.run_blocked_reason(by) || "This is no longer waiting to be run." unless held.claim_run!(by: by)

    conversation = held.conversation
    conversation.expect_reply!
    ConversationReplyJob.perform_later(conversation.id, by.id, held.id)
    tell!(held)
    nil
  end

  def self.dismiss!(held, by:)
    blocked = held.dismiss_blocked_reason(by)
    return blocked if blocked
    unless held.move!(from: Chat::HeldCall::OPEN, to: Chat::HeldCall::STATUS_DISMISSED, decided_by_id: by.id, decided_at: Time.current)
      return "This is no longer waiting to be run."
    end

    held.approval.dismiss!
    tell!(held)
    nil
  end

  # Asks the approvers again for exactly the same call, as the person who asked it. Nothing runs here either.
  def self.ask_again!(held, by:)
    blocked = held.ask_again_blocked_reason(by)
    return blocked if blocked

    case held.ask_again!
    when Chat::HeldCall::ASKED_AGAIN
      tell!(held)
      nil
    when Chat::HeldCall::NO_RULE_NOW then NO_RULE_NOW
    else format(NOT_ALLOWED_NOW, asker: held.asker_name)
    end
  end

  # Longer than any check takes, so a call still checking after it lost its job to a stopped worker.
  CHECK_LOST_AFTER = 15.minutes

  # From the recovery sweep. A check whose job was lost runs again, at most once per CHECK_LOST_AFTER, since the claim
  # moves the row on. A call left running by a turn that will not run again ends saying so.
  def self.recover!
    Chat::HeldCall.where(status: Chat::HeldCall::STATUS_CHECKING, updated_at: ...CHECK_LOST_AFTER.ago).find_each do |held|
      relooked = Chat::HeldCall.where(id: held.id, status: Chat::HeldCall::STATUS_CHECKING, updated_at: held.updated_at)
                               .update_all(updated_at: Time.current)
      HeldCallCheckJob.perform_later(held.id) if relooked.positive?
    end
    Chat::HeldCall.where(status: Chat::HeldCall::STATUS_RUNNING, decided_at: ...Conversation::REPLY_CEILING.ago).find_each { |held| give_up!(held) }
  end

  # The call may or may not have gone through, so whoever asked is told to look before asking again. Once, by the move.
  def self.give_up!(held)
    tell!(held) if held.finish!(ok: false, result: COULD_NOT_FINISH)
  end

  # Runs the claimed call through the gateway with its approval, as whoever asked, from the chat's turn. Returns the text
  # the call answered, which the turn hands to Halon, and keeps a short form of it with the call.
  def self.execute!(held)
    approval = held.approval
    turn = Conversation::Turn.new(held.conversation, asker: held.asker)
    said = run_call(turn, held, approval)
    held.ran!(said)
    tell!(held)
    said
  rescue StandardError => error
    Rails.logger.warn({ event: "held_call.run_failed", held_call_id: held.id, error: error.class.name }.to_json)
    held.finish!(ok: false, result: COULD_NOT_FINISH)
    tell!(held)
    COULD_NOT_FINISH
  end

  def self.run_call(turn, held, approval)
    tool = Integration::Tool.in_workspace(held.workspace).find { |each| each.action_key == approval.action_key }
    if tool
      environment_entry = held.workspace.catalog_entries.find_by(id: approval.scope["environment"]) if approval.scope["environment"]
      return Chat::Tools::Connection.new(turn, tool).run(approval.params, environment_entry: environment_entry, tool_call_id: nil,
                                                                         shown_as: held.tool_name, approval_id: approval.id)
    end

    tool_class = Mcp::Tools.all.find { |each| each.name_value.to_s == held.tool_name }
    return "#{held.tool_name} is no longer a tool here, so it did not run." unless tool_class

    action = Ability::Action.lookup(approval.action_key, held.workspace)
    Chat::Tools::Firefight.new(turn, tool_class, action).run_approved(approval.action_key, approval.params, approval_id: approval.id)
  end
  private_class_method :run_call

  # What Halon is told at the start of its next turn about calls that ended without running, once each.
  def self.untold_note(chat)
    ended = chat.held_calls.untold.includes(:approval).to_a
    return nil if ended.empty?

    chat.held_calls.where(id: ended.map(&:id)).update_all(told_at: Time.current)
    lines = ended.map { |held| "- #{named(held)}: #{outcome_words(held)}" }
    "Calls you made earlier that were held for approval, and what became of them since. Only one that says it ran, ran:\n#{lines.join("\n")}"
  end

  # What Halon reads once the person ran the call, before it tells them how it went.
  def self.ran_note(held, said)
    who = held.decided_by&.display_name || "The person"
    "#{who} ran the approved call #{named(held)}. It answered:\n#{said}\n" \
      "Tell them in a sentence or two what it did, from that answer. It ran once. Never call it again unless they ask."
  end

  def self.outcome_words(held)
    case held.status
    when Chat::HeldCall::STATUS_RAN then "#{held.decided_by&.display_name || 'The person'} ran it once it was approved, and it went through."
    when Chat::HeldCall::STATUS_FAILED then "#{held.decided_by&.display_name || 'The person'} ran it once it was approved, and it failed: #{held.result}"
    when Chat::HeldCall::STATUS_DENIED then "#{approver_name(held.approval)} denied it."
    when Chat::HeldCall::STATUS_DISMISSED then "#{held.decided_by&.display_name || 'The person'} dismissed it after it was approved."
    else "it was approved but nobody ran it within the hour, so the approval expired."
    end
  end
  private_class_method :outcome_words

  def self.shown(held)
    approval = held.approval
    status = held.shown_status
    report = (Chat::CurrentState::Report.new(state: held.checked_state, change: held.state_change, checked_at: held.state_checked_at) if held.state_change)
    Shown.new(
      id: held.id, conversation_id: held.chat.owner_id, status: status, headline: headline(held, status), call: call_name(held),
      target: held.target, asked: asked(held), state: report&.state, warning: report&.warning, checked_at: held.state_checked_at,
      expires_at: approval.run_expires_at, decided_by: held.decided_by&.display_name, result: held.result, offers: held.offers
    )
  end

  def self.headline(held, status)
    who = approver_name(held.approval)
    call = named(held)
    case status
    when Chat::HeldCall::STATUS_WAITING then "Waiting for approval: #{call}."
    when Chat::HeldCall::STATUS_CHECKING, Chat::HeldCall::STATUS_READY then "#{who} approved: #{call}. Run it now?"
    when Chat::HeldCall::STATUS_RUNNING then "Running #{call}."
    when Chat::HeldCall::STATUS_RAN then "Ran #{call}."
    when Chat::HeldCall::STATUS_FAILED then "#{call} did not go through."
    when Chat::HeldCall::STATUS_DISMISSED then "Dismissed: #{call}. It did not run."
    when Chat::HeldCall::STATUS_DENIED then "#{who} denied: #{call}. Nothing ran."
    else "The approval for #{call} expired before anyone ran it."
    end
  end
  private_class_method :headline

  # The call by its own name, on what it reaches, as the confirmation names it.
  def self.named(held)
    held.target ? "#{call_name(held)} on #{held.target}" : call_name(held)
  end

  def self.call_name(held)
    tool = Chat::Tools::Target.connection_tool(held.workspace, held.tool_name)
    (tool ? tool.name : held.tool_name).to_s.tr("_.", "  ").humanize
  end

  def self.asked(held) = Chat::Tools.shown_arguments(held.approval.params)

  def self.approver_name(approval) = approval.approver&.actor_display_name || "An approver"

  # Approved and denied are news, so they are posted where the chat lives: its thread for a chat in a channel, and the
  # asker's direct messages for one on the dashboard, where the page redraws itself too. Everything after redraws that
  # message, since an edit notifies nobody.
  NEWS = [ Chat::HeldCall::STATUS_CHECKING, Chat::HeldCall::STATUS_DENIED ].freeze

  def self.tell!(held)
    held.reload
    Conversation::LiveDelivery.held_call_moved(held.conversation)
    return if held.message_id.blank? && !NEWS.include?(held.status)

    shown = shown(held)
    adapter = WorkspaceAdapter.for(held.workspace)
    if held.message_id.present?
      adapter.update_held_call(channel_id: held.message_channel_id, message_id: held.message_id, held_call: shown,
                               direct: held.conversation.thread_id.blank?)
    else
      posted = post(adapter, held, shown)
      held.update_columns(message_channel_id: posted[:channel_id], message_id: posted[:message_id]) if posted
    end
  rescue AdapterError => error
    Rails.logger.warn({ event: "held_call.untold", held_call_id: held.id, error: error.class.name }.to_json)
  end

  def self.post(adapter, held, shown)
    conversation = held.conversation
    if conversation.thread_id.present?
      adapter.post_held_call(channel_id: conversation.channel_id, thread_id: conversation.thread_id, held_call: shown)
    elsif held.asker.try(:platform_user_id).present?
      adapter.post_held_call_to_user(user_id: held.asker.platform_user_id, held_call: shown)
    end
  end
  private_class_method :post
end
