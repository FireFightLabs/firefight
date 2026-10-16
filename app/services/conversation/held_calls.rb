# A call an approval rule held in a chat, from its approval to its run. It is asked in the chat's thread as soon as it is
# held, with Approve and Deny for its approvers, who are asked directly too. Approving it runs it at once, as whoever
# asked, through the gateway again with the approval, and its message follows the run as a checklist until it says how it
# went. A call approved before approving ran it waits for Run, as it always did (checking and ready).
module Conversation::HeldCalls
  # What the card and the platform's message draw. call and target name the call as the confirmation does ("Api request"
  # on "Production (Hosting), project shop"), and action as the request does ("pause dev-web"). line is the one line under
  # the headline. offers is what may be done now, whoever does it. progress is how far a code change got while it runs.
  Shown = Data.define(
    :id, :conversation_id, :status, :headline, :call, :target, :asked, :state, :warning, :checked_at, :expires_at,
    :decided_by, :result, :offers, :action, :line, :approval_id, :approved_by, :progress, :link
  )

  COULD_NOT_FINISH = "Firefight could not finish this call. Check whether it went through before asking for it again.".freeze

  NO_RULE_NOW = "No approval rule holds this call any more, so ask Halon to make it again.".freeze
  NOT_ALLOWED_NOW = "%<asker>s may no longer make this call, so it cannot be asked for again.".freeze

  # From ApprovalResumption once an approver approved. Approving is the decision to run it, so it runs at once, through
  # the chat's next turn, and Halon says how it went. It runs as whoever asked, and the turn carries on as them, except in
  # a tracker's issue, whose chat acts as Firefight and carries on as the approver.
  def self.approved!(approval)
    held = Chat::HeldCall.find_by(approval: approval)
    return unless held

    approver = approval.approver
    decided_by = approver if approver.is_a?(WorkspaceMembership)
    return unless held.move!(from: Chat::HeldCall::STATUS_WAITING, to: Chat::HeldCall::STATUS_RUNNING, decided_by_id: decided_by&.id,
                             decided_at: Time.current)

    conversation = held.conversation
    conversation.expect_reply!
    asker = held.asker
    turn_as = !conversation.try(:issue?) && asker.is_a?(WorkspaceMembership) ? asker : decided_by
    ConversationReplyJob.perform_later(conversation.id, turn_as&.id, held.id)
    tell!(held, news: true)
  end

  # Held, so it is asked in the chat's thread, after the turn's own writes (HeldCallPostJob). held is false when nothing
  # was kept, as in an outside agent's chat.
  def self.ask_where_held(held)
    HeldCallPostJob.perform_later(held.id) if held.is_a?(Chat::HeldCall)
  end

  def self.held!(held) = tell!(held)

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

    lapsing = held.approval
    still_approved = lapsing.approved?
    case held.ask_again!
    when Chat::HeldCall::ASKED_AGAIN
      tell!(held)
      ask_where_held(held.chat.held_calls.where(status: Chat::HeldCall::STATUS_WAITING, tool_call_id: held.tool_call_id).order(:created_at).last)
      # An approval that lapsed only now, in asking again, says so where it was asked.
      ApprovalNotificationService.mark_resolved!(lapsing) if still_approved && lapsing.reload.expired?
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
  # progress hears how a code change is going as it runs, which the turn shows on the call's message.
  def self.execute!(held, progress: nil)
    approval = held.approval
    turn = Conversation::Turn.new(held.conversation, asker: held.asker)
    turn.listen_to_progress { |_key, update| progress.call(update) } if progress
    said = run_call(turn, held, approval)
    held.ran!(said)
    ended!(held)
    said
  rescue StandardError => error
    Rails.logger.warn({ event: "held_call.run_failed", held_call_id: held.id, error: error.class.name }.to_json)
    held.finish!(ok: false, result: COULD_NOT_FINISH)
    ended!(held)
    COULD_NOT_FINISH
  end

  # How it went goes on its own message and on every message that asked its approvers.
  def self.ended!(held)
    tell!(held)
    ApprovalNotificationService.mark_resolved!(held.approval)
  end
  private_class_method :ended!

  # A code change got further, so its message is redrawn with how it stands this moment.
  def self.moved!(held, progress: nil) = tell!(held, progress: progress)

  def self.run_call(turn, held, approval)
    tool = Integration::Tool.by_action_key(held.workspace, approval.action_key)
    if tool
      environment_entry = held.workspace.catalog_entries.find_by(id: approval.scope["environment"]) if approval.scope["environment"]
      return Chat::Tools::Connection.new(turn, tool).run(approval.params, environment_entry: environment_entry, tool_call_id: held.tool_call_id,
                                                                         shown_as: held.tool_name, approval_id: approval.id)
    end

    if held.tool_name == Chat::Tools::Browser::NAME
      return Chat::Tools::Browser.new(turn).run_approved(approval.params, approval_id: approval.id, tool_call_id: held.tool_call_id)
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
    else "it was approved but nobody ran it within #{Integrations::Capabilities::History.duration(Ability::Approval::RUN_WINDOW.to_i)}, so the approval expired."
    end
  end
  private_class_method :outcome_words

  # progress is a code change's work as it stands this moment, shown over the copy kept at the chat's pace.
  def self.shown(held, progress: nil)
    approval = held.approval
    status = held.shown_status
    report = (Chat::CurrentState::Report.new(state: held.checked_state, change: held.state_change, checked_at: held.state_checked_at) if held.state_change)
    action = action_of(held)
    work = progress || Chat::StepProgress.find_by(chat_id: held.chat_id, tool_call_id: held.tool_call_id)&.work
    approved_by = (approver_name(approval) if approval.approver)
    Shown.new(
      id: held.id, conversation_id: held.chat.owner_id, status: status, headline: headline(action, status), call: call_name(held),
      target: held.target, asked: asked(held), state: report&.state, warning: report&.warning, checked_at: held.state_checked_at,
      expires_at: approval.run_expires_at, decided_by: held.decided_by&.display_name, result: held.result, offers: held.offers,
      action: action, line: line(held, status, approved_by), approval_id: approval.id, approved_by: approved_by, progress: work,
      link: work&.pull_request.presence
    )
  end

  # What Halon asked to do, in its own words as the chat's request names it ("pause dev-web"), or the call by its own
  # name on what it reaches when it wrote none.
  def self.action_of(held)
    tool_call = held.chat.tool_calls.find_by(tool_call_id: held.tool_call_id)
    worded = tool_call && Chat::Tools.words_for_person(tool_call.arguments)
    worded ? Chat::Tools.confirmation(tool_call).action : named(held).downcase_first
  end

  def self.headline(action, status)
    case status
    when Chat::HeldCall::STATUS_WAITING, Chat::HeldCall::STATUS_CHECKING, Chat::HeldCall::STATUS_READY then "#{Chat::Tools::WANTS_TO} #{action}"
    when Chat::HeldCall::STATUS_RUNNING then action.upcase_first
    when Chat::HeldCall::STATUS_RAN then "Done: #{action}"
    when Chat::HeldCall::STATUS_FAILED then "Failed: #{action}"
    when Chat::HeldCall::STATUS_DISMISSED then "Dismissed: #{action}"
    when Chat::HeldCall::STATUS_DENIED then "Denied: #{action}"
    when Chat::HeldCall::STATUS_ASKED_AGAIN then "Asked again: #{action}"
    else "Expired: #{action}"
    end
  end
  private_class_method :headline

  # The one line under the headline: who it waits on, who approved it and how it stands, or why it ended.
  def self.line(held, status, approved_by)
    case status
    when Chat::HeldCall::STATUS_WAITING then "Waiting for #{waiting_on(held.approval)} to approve it."
    when Chat::HeldCall::STATUS_CHECKING then "Approved by #{approved_by}. Halon is checking how things stand now."
    when Chat::HeldCall::STATUS_READY then "Approved by #{approved_by}. Run it now?"
    when Chat::HeldCall::STATUS_RUNNING then "Approved by #{approved_by}, working on it."
    when Chat::HeldCall::STATUS_RAN then "Approved by #{approved_by}."
    when Chat::HeldCall::STATUS_FAILED then held.result.presence || COULD_NOT_FINISH
    when Chat::HeldCall::STATUS_DISMISSED then "Dismissed by #{held.decided_by&.display_name || 'someone'}. It did not run."
    when Chat::HeldCall::STATUS_DENIED then "Denied by #{approver_name(held.approval)}. Nothing ran."
    when Chat::HeldCall::STATUS_ASKED_AGAIN then "Asked for approval again."
    else "The approval expired before it ran. Ask for it again if it is still needed."
    end
  end
  private_class_method :line

  # Who may approve it, in a few words: the people named, else the role.
  def self.waiting_on(approval)
    named = approval.named_approvers? ? approval.human_approvers.map(&:display_name) : []
    return named.to_sentence(two_words_connector: " or ", last_word_connector: " or ") if named.any?

    approval.required_role == WorkspaceMembership.roles[:owner] ? "a workspace owner" : "a workspace admin"
  end
  private_class_method :waiting_on

  # The call by its own name, on what it reaches, as the confirmation names it.
  def self.named(held)
    held.target ? "#{call_name(held)} on #{held.target}" : call_name(held)
  end

  def self.call_name(held)
    tool = Chat::Tools::Target.label(held.workspace, held.tool_name)
    (tool ? tool.name : held.tool_name).to_s.tr("_.", "  ").humanize
  end

  def self.asked(held) = Chat::Tools.shown_arguments(held.approval.params)

  def self.approver_name(approval) = approval.approver&.actor_display_name || "An approver"

  # Approved and denied are news, so they are posted where the chat lives: its thread for a chat in a channel, and the
  # asker's direct messages for one on the dashboard, where the page redraws itself too. Everything after redraws that
  # message, since an edit notifies nobody.
  # Held is news in a thread, where its approvers are asked, and never by direct message, since the person who asked sees
  # it in the chat they are in. Approved is news too (news: true), since it runs at once and nobody was there to press Run.
  NEWS = [ Chat::HeldCall::STATUS_CHECKING, Chat::HeldCall::STATUS_DENIED ].freeze

  def self.tell!(held, progress: nil, news: false)
    held.reload
    Conversation::LiveDelivery.held_call_moved(held.conversation)
    return if held.message_id.blank? && !news && !news?(held)

    shown = shown(held, progress: progress)
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

  def self.news?(held)
    return held.conversation.thread_id.present? if held.status == Chat::HeldCall::STATUS_WAITING

    NEWS.include?(held.status)
  end
  private_class_method :news?

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
