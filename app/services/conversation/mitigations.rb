# Changes customers feel for a while (Chat::Mitigation): proposed when Halon pauses on one, started when it runs, its undo
# written from what it returned, a reminder before it runs out, and its undo run when it does, unless someone kept it.
# The undo runs as whoever asked for the change, through the same tools and the gateway, so grants, approval rules and
# the activity log apply as for any call. A change Halon made without asking is kept the same way, as made, and said
# where the chat is with Undo when something puts it back.
module Conversation::Mitigations
  KIND_REMINDER = "reminder".freeze
  KIND_ENDED = "ended".freeze
  KIND_KEPT = "kept".freeze
  KIND_EXTENDED = "extended".freeze
  KIND_MADE = "made".freeze
  # Marks an undo step as the registry's fixed call, the only kind Firefight runs itself.
  DECLARED = "declared".freeze

  # What a person or the platform is shown, the same on the dashboard and in Slack. keeps is whether Keep it and One
  # more hour are offered while it is in place, and undoable whether Undo now is.
  Notice = Data.define(:id, :kind, :title, :text, :live, :conversation_id, :keeps, :undoable) do
    def initialize(keeps: true, undoable: true, **) = super
  end

  # Kept at the pause, so the person sees and can change when it is undone. A call that runs without a pause, such as
  # one allowed for the rest of the chat, is kept as it runs, with the default time.
  def self.propose!(agent_run, call_id:, tool:, environment_entry:, arguments:, tool_name:, target: nil, intent: nil)
    chat = agent_run.chat
    Chat::Mitigation.for_call(chat, call_id) || Chat::Mitigation.create!(
      chat: chat, workspace: agent_run.workspace, asker: agent_run.acting_principal, tool_call_id: call_id.to_s, tool_name: tool_name,
      action_key: tool.action_key, environment_id: environment_entry&.id, arguments: arguments.to_h, target: target, intent: intent,
      duration_minutes: Chat::Mitigation::DEFAULT_MINUTES
    )
  rescue ActiveRecord::RecordNotUnique
    Chat::Mitigation.for_call(chat, call_id)
  end

  # The person's choice on the confirmation. nil keeps it.
  # One guarded update, so a choice that lands after the call ran never changes its time.
  def self.choose!(chat, tool_call_id, value)
    Chat::Mitigation.where(chat: chat, tool_call_id: tool_call_id.to_s, status: Chat::Mitigation::STATUS_PROPOSED)
                    .update_all(duration_minutes: Chat::Mitigation.chosen_minutes(value), updated_at: Time.current)
  end

  # The call ran. Its time starts now, its undo is written from what it returned, and Halon reads when it ends. A call
  # that failed changed nothing, so nothing is undone.
  def self.ran!(mitigation, ok:, result:)
    unless ok
      mitigation.move!(from: Chat::Mitigation::STATUS_PROPOSED, to: Chat::Mitigation::STATUS_CANCELLED)
      return nil
    end
    step = Chat::Plan::Step.running_change(mitigation.chat)
    # A step of a plan's undo puts something back, so it is never itself counted down and undone.
    if step&.plan&.undo?
      mitigation.move!(from: Chat::Mitigation::STATUS_PROPOSED, to: Chat::Mitigation::STATUS_CANCELLED)
      return nil
    end
    return nil unless mitigation.start!(result: result_text(result), undo: declared_undo(mitigation, result))

    mitigation.update_columns(plan_step_id: step.id) if step

    Conversation::LiveDelivery.safeguard_moved(mitigation.conversation)
    started_note(mitigation)
  end

  # Undo was pressed on a plan, so a change its steps made that is still in place is put back by the plan's undo, and
  # Firefight stops counting it down, so nothing is undone twice.
  def self.handed_to_plan!(plan)
    Chat::Mitigation.where(plan_step_id: plan.steps.select(:id), status: [ Chat::Mitigation::STATUS_ACTIVE, Chat::Mitigation::STATUS_KEPT ])
                    .update_all(status: Chat::Mitigation::STATUS_WITH_PLAN, outcome: "Put back by the plan's undo instead.", ended_at: Time.current,
                                told_at: Time.current, updated_at: Time.current)
    Conversation::LiveDelivery.safeguard_moved(plan.conversation)
  end

  # A change Halon made without asking ran. A change customers feel is still counted down as it was, and anything else is
  # kept as made, in place until someone undoes it. Either way the person sees it with why it was not asked, where the
  # chat is. undoable is whether something puts it back. Returns what Halon reads, or nil when it was not kept.
  # inverse is the fixed call that puts it back (Integrations::SafeChanges::Inverse), or nil for none, which offers no Undo.
  def self.made!(agent_run, call_id:, tool:, environment_entry:, arguments:, result:, unasked:, inverse:)
    chat = agent_run.chat
    return nil if chat.nil? || unasked.nil? || call_id.blank?

    mitigation = Chat::Mitigation.for_call(chat, call_id)
    if mitigation
      mitigation.update_columns(unasked_reason: unasked.reason, allowance_id: unasked.allowance_id)
    else
      mitigation = Chat::Mitigation.create!(
        chat: chat, workspace: agent_run.workspace, asker: agent_run.acting_principal, tool_call_id: call_id.to_s, action_key: tool.action_key,
        environment_id: environment_entry&.id, arguments: arguments.to_h, status: Chat::Mitigation::STATUS_MADE, started_at: Time.current,
        told_at: Time.current, result: Chat::SecretFree.redacted(result_text(result)).truncate(Chat::Mitigation::RESULT_LIMIT),
        unasked_reason: unasked.reason, allowance_id: unasked.allowance_id, **undo_of(inverse, environment_entry), **called(agent_run, chat, call_id, tool)
      )
    end
    tell!(mitigation, KIND_MADE, made_words(mitigation))
    made_note(mitigation)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # The undo as one step ready to run, the declared call on the same connection and environment, or none.
  def self.undo_of(inverse, environment_entry)
    return { undo_state: Chat::Mitigation::UNDO_NO_INVERSE } unless inverse

    step = undo_step(inverse, environment_entry)
    { undo_state: Chat::Mitigation::UNDO_READY, undo_note: "#{step['description']}.", undo_steps: [ step ] }
  end
  private_class_method :undo_of

  def self.undo_step(inverse, environment_entry)
    { "description" => "#{inverse.tool.name.to_s.tr('_', ' ').upcase_first} on #{inverse.tool.integration.display_name}",
      "action_key" => inverse.tool.action_key, "arguments" => inverse.arguments, "environment_id" => environment_entry&.id, DECLARED => true }
  end

  # The fixed call the registry declares to put a temporary change back, from what it was sent and answered, or nil.
  def self.declared_undo(mitigation, result)
    tool = Integration::Tool.by_action_key(mitigation.workspace, mitigation.action_key)
    inverse = tool && Integrations::SafeChanges.inverse(tool, mitigation.arguments, result.is_a?(Hash) ? result : {})
    inverse && undo_step(inverse, (CatalogEntry.find_by(id: mitigation.environment_id) if mitigation.environment_id))
  end
  private_class_method :declared_undo

  # The name Halon called it by, what it reaches and the change in Halon's few words, read from the call itself.
  def self.called(agent_run, chat, call_id, tool)
    call = chat.tool_calls.find_by(tool_call_id: call_id.to_s)
    name = call&.name || tool.model_facing_name
    arguments = call&.arguments.to_h
    { tool_name: name, target: Chat::Tools::Target.describe(agent_run, name, arguments),
      intent: Chat::Tools.short_title_of(arguments) || Chat::Tools.intent_of(arguments) }
  end
  private_class_method :called

  def self.made_words(mitigation)
    undo = if mitigation.live?
      mitigation.undo_state == Chat::Mitigation::UNDO_NO_INVERSE ? "There is no Undo for this change." : "Undo puts it back."
    end
    [ "#{mitigation.label}.", mitigation.unasked_words, undo ].compact.join(" ")
  end

  def self.made_note(mitigation)
    return started_note(mitigation) unless mitigation.made?

    undo = mitigation.undo_state == Chat::Mitigation::UNDO_NO_INVERSE ? "with no Undo" : "with Undo"
    "This ran without asking the person, #{mitigation.unasked_because}. They see it in the chat #{undo}. Say what you changed, in a sentence."
  end

  def self.started_note(mitigation)
    if mitigation.kept?
      "The person chose to keep this, so Firefight will not undo it. Say so, and that it stays until someone changes it back."
    else
      "Firefight undoes this in #{Chat::Mitigation.duration_words(mitigation.duration_minutes)}, at #{mitigation.expires_at.utc.to_fs(:time)} UTC, " \
        "and reminds the person #{Chat::Mitigation::REMIND_BEFORE.inspect} before, unless someone keeps it. Tell them, in a sentence."
    end
  end

  def self.result_text(result)
    return result.to_s unless result.is_a?(Hash)

    Array(result["content"]).filter_map { |part| part["text"] }.join("\n")
  end
  private_class_method :result_text

  # Due within REMIND_BEFORE, said once.
  def self.remind!(mitigation)
    return unless mitigation.claim_reminder!

    left = Chat::Mitigation.duration_words(((mitigation.expires_at - Time.current) / 60).ceil.clamp(1, nil))
    how = mitigation.undo_state == Chat::Mitigation::UNDO_BY_HAND ? "It is then due to be undone by hand. #{mitigation.undo_note}" : "Firefight then undoes it."
    tell!(mitigation, KIND_REMINDER, "#{mitigation.title} ends in about #{left}. #{how} Keep it or extend it if it is still needed.")
  end

  # Run out and not kept. The undo runs, or a person is told it is due by hand.
  def self.expire!(mitigation)
    return unless mitigation.move!(from: Chat::Mitigation::STATUS_ACTIVE, to: Chat::Mitigation::STATUS_UNDOING, claimed_at: Time.current)

    undo!(mitigation, by: nil)
  end

  # Undo now, pressed by a person. Returns why it was not undone, or nil.
  def self.undo_now!(mitigation, by:)
    blocked = mitigation.undo_blocked_reason(by)
    return blocked if blocked
    return "This was just changed by someone else." unless mitigation.move!(from: [ Chat::Mitigation::STATUS_ACTIVE, Chat::Mitigation::STATUS_KEPT, Chat::Mitigation::STATUS_MADE ],
                                                                             to: Chat::Mitigation::STATUS_UNDOING, claimed_at: Time.current, ended_by_id: by&.id)

    MitigationUndoRunJob.perform_later(mitigation.id)
    nil
  end

  def self.keep!(mitigation, by:)
    blocked = mitigation.keep_blocked_reason(by)
    return blocked if blocked
    return "This was just changed by someone else." unless mitigation.move!(from: Chat::Mitigation::STATUS_ACTIVE, to: Chat::Mitigation::STATUS_KEPT,
                                                                             expires_at: nil, ended_by_id: by.id)

    tell!(mitigation, KIND_KEPT, "#{by.display_name} kept #{mitigation.title}, so Firefight will not undo it. Undo it from here when it is no longer needed.")
    nil
  end

  def self.extend!(mitigation, by:)
    blocked = mitigation.extend_blocked_reason(by)
    return blocked if blocked

    later = [ mitigation.expires_at, Time.current ].max + Chat::Mitigation::EXTEND_BY
    moved = Chat::Mitigation.where(id: mitigation.id, status: Chat::Mitigation::STATUS_ACTIVE, expires_at: mitigation.expires_at)
                            .update_all(expires_at: later, reminded_at: nil, updated_at: Time.current)
    return "This was just changed by someone else." unless moved == 1

    mitigation.reload
    tell!(mitigation, KIND_EXTENDED, "#{by.display_name} gave #{mitigation.title} #{Chat::Mitigation.duration_words(Chat::Mitigation::EXTEND_BY.in_minutes.to_i)} " \
                                     "more. Firefight now undoes it at #{mitigation.expires_at.utc.to_fs(:time)} UTC.")
    nil
  end

  # Claimed as undoing by whoever started it. Each step runs in order as the asker, and the first that does not go
  # through stops it, said with why.
  def self.undo!(mitigation, by:)
    return in_chat!(mitigation, by: by) if mitigation.undo_state == Chat::Mitigation::UNDO_IN_CHAT
    if mitigation.undo_state != Chat::Mitigation::UNDO_READY
      ending!(mitigation, Chat::Mitigation::STATUS_DUE_BY_HAND, "#{mitigation.title} is due to be undone, and Firefight cannot do it itself. " \
                                                                 "#{mitigation.undo_note.presence || 'Its undo is not written yet.'}")
      return
    end

    turn = Conversation::Turn.new(mitigation.conversation, asker: mitigation.asker)
    mitigation.undo_steps.each do |step|
      outcome = run_step(turn, mitigation, step)
      next if outcome == :ran

      status = outcome == :held ? Chat::Mitigation::STATUS_UNDO_HELD : Chat::Mitigation::STATUS_UNDO_FAILED
      return ending!(mitigation, status, outcome_words(mitigation, outcome, step, by))
    end
    ending!(mitigation, Chat::Mitigation::STATUS_UNDONE, "#{undone_by(mitigation, by)} #{mitigation.title}: #{mitigation.undo_note}")
  rescue StandardError => error
    Rails.logger.warn({ event: "mitigation.undo_broke", mitigation_id: mitigation.id, error: error.class.name }.to_json)
    ending!(mitigation, Chat::Mitigation::STATUS_UNDO_FAILED, "Firefight could not undo #{mitigation.title}, since something went wrong on its side. Undo it by hand.")
  end

  # The worker undoing it died part way, so whether it went through is unknown and the person is told to look.
  def self.give_up!(mitigation)
    ending!(mitigation, Chat::Mitigation::STATUS_UNDO_FAILED,
            "Firefight was stopped while undoing #{mitigation.title}, so it may or may not be undone. Check it, and undo it by hand if it is still in place.")
  end

  def self.undone_by(_mitigation, by) = by ? "#{by.display_name} undid" : "Time was up, so Firefight undid"
  private_class_method :undone_by

  # Every undo Firefight runs itself is a fixed declared call (run_inverse). A step written before that, by a model, is
  # never run, and its change is put back in the chat instead.
  def self.run_step(turn, mitigation, step)
    return [ :failed, "its undo was not one Firefight declares, so put it back by hand" ] unless step[DECLARED]

    run_inverse(turn, mitigation, step)
  end
  private_class_method :run_step

  # No fixed call puts it back, so Halon is asked in the chat to put it back, where its call goes through the resolver
  # and the card like any change, as whoever asked for the change.
  def self.in_chat!(mitigation, by:)
    conversation = mitigation.conversation
    who = by ? "#{by.display_name} pressed Undo now on" : "Time is up for"
    mitigation.chat.nudge!("#{who} #{mitigation.title} (#{mitigation.label}), which no fixed call puts back. Put it back now with the tool " \
                           "that does, from what the call returned earlier in this chat. It asks the person like any change.")
    ConversationReplyJob.perform_later(conversation.id, (mitigation.asker.id if mitigation.asker.is_a?(WorkspaceMembership)))
    ending!(mitigation, Chat::Mitigation::STATUS_UNDO_HELD, "Halon puts #{mitigation.title} back in the chat, and asks first like any change.")
  end
  private_class_method :in_chat!

  # The declared undo of a change made without asking, only ever through a tool that may be one (SafeChanges.inverse_allowed?)
  # of the same connection, in the environment the change ran in, through the gateway as the asker, so grants, approval
  # rules and the activity log apply.
  def self.run_inverse(turn, mitigation, step)
    tool = Integration::Tool.by_action_key(mitigation.workspace, step["action_key"])
    made_on = Integration::Tool.by_action_key(mitigation.workspace, mitigation.action_key)
    return [ :failed, "the tool it runs with is switched off or gone" ] unless tool&.enabled? && made_on
    return [ :failed, "it would reach another connection" ] unless tool.integration_id == made_on.integration_id
    return [ :failed, "#{tool.name} may not undo a change" ] unless Integrations::SafeChanges.inverse_allowed?(tool)

    entry = (CatalogEntry.find_by(id: step["environment_id"], workspace_id: mitigation.workspace_id) if step["environment_id"])
    connection = Chat::Tools::Connection.new(turn, tool)
    said = connection.run(step["arguments"].to_h, environment_entry: entry, tool_call_id: nil, shown_as: tool.model_facing_name, inverse: nil)
    return :held if connection.waiting?
    return [ :failed, said.to_s.lines.first.to_s.strip.truncate(300) ] if connection.failed?

    :ran
  end
  private_class_method :run_inverse

  def self.outcome_words(mitigation, outcome, step, _by)
    # A held call runs as soon as it is approved (Conversation::HeldCalls.approved!), so there is no Run to wait for.
    return "Undoing #{mitigation.title} needs an approval, so it waits in the chat until someone approves it, and then it runs." if outcome == :held

    "Firefight could not undo #{mitigation.title} at the step \"#{step['description']}\": #{outcome.last}. Undo it by hand."
  end
  private_class_method :outcome_words

  # Halon was told of a change made without asking as it ran, so it hears again once that change is undone.
  def self.ending!(mitigation, status, text)
    told = { told_at: nil } if mitigation.made_unasked?
    mitigation.move!(from: Chat::Mitigation::STATUS_UNDOING, to: status, ended_at: Time.current, outcome: Chat::SecretFree.redacted(text), **told.to_h)
    tell!(mitigation, KIND_ENDED, text)
  end
  private_class_method :ending!

  # Said where the chat is: its thread, the asker's direct messages unless the thread is one, and the dashboard.
  def self.tell!(mitigation, kind, text)
    conversation = mitigation.conversation
    Conversation::LiveDelivery.safeguard_moved(conversation)
    notice = notice(mitigation, kind, text)
    adapter = WorkspaceAdapter.for(mitigation.workspace)
    in_thread = conversation.thread_id.present?
    posted = post(mitigation) { adapter.post_mitigation_notice(channel_id: conversation.channel_id, thread_id: conversation.thread_id, notice: notice) } if in_thread
    user_id = mitigation.asker.try(:platform_user_id)
    unless user_id.blank? || !timed?(mitigation) || (in_thread && adapter.direct_conversation?(channel_id: conversation.channel_id))
      posted = post(mitigation) { adapter.post_mitigation_notice_to_user(user_id: user_id, notice: notice) } || posted
    end
    mitigation.update_columns(message_channel_id: posted[:channel_id], message_id: posted[:message_id]) if posted.is_a?(Hash) && posted[:message_id]
    notice
  end

  # A change made without asking that nothing counts down stays where the chat is, since nobody needs reminding of it.
  # One with a time still reaches the asker wherever they are.
  def self.timed?(mitigation) = !(mitigation.made_unasked? && mitigation.duration_minutes.nil?)

  def self.notice(mitigation, kind, text)
    Notice.new(id: mitigation.id, kind: kind, title: mitigation.title, text: text, live: mitigation.live?, keeps: timed?(mitigation),
               undoable: mitigation.undo_state != Chat::Mitigation::UNDO_NO_INVERSE,
               conversation_id: (mitigation.conversation.id if mitigation.conversation.personal?))
  end

  def self.post(mitigation)
    yield
  rescue AdapterError => error
    Rails.logger.warn({ event: "mitigation.untold", mitigation_id: mitigation.id, error: error.class.name }.to_json)
    nil
  end
  private_class_method :post

  # Pressed on a message the platform shows. The message is redrawn so it no longer offers what is done. Returns why
  # nothing was done, or nil.
  def self.pressed!(mitigation, action, by:, channel_id:, message_id:)
    blocked = public_send(action, mitigation, by: by)
    redraw(mitigation, channel_id, message_id)
    blocked
  end

  def self.redraw(mitigation, channel_id, message_id)
    return if channel_id.blank? || message_id.blank?

    mitigation.reload
    text = mitigation.outcome.presence || "#{mitigation.title} is #{mitigation.kept? ? 'kept' : 'still in place'}."
    WorkspaceAdapter.for(mitigation.workspace).update_mitigation_notice(channel_id: channel_id, message_id: message_id,
                                                                        notice: notice(mitigation, KIND_ENDED, text))
  rescue AdapterError => error
    Rails.logger.warn({ event: "mitigation.redraw_failed", mitigation_id: mitigation.id, error: error.class.name }.to_json)
  end
  private_class_method :redraw

  # What Halon hears at its next turn about changes that were kept or undone since it last looked, once each.
  def self.untold_note(chat)
    ended = chat.mitigations.untold.to_a
    return nil if ended.empty?

    Chat::Mitigation.where(id: ended.map(&:id)).update_all(told_at: Time.current)
    lines = ended.map { |mitigation| "- #{mitigation.title}: #{mitigation.outcome.presence || 'kept, so it stays until someone changes it back.'}" }
    "Changes you made earlier that Firefight keeps track of, temporary or made without asking, and what became of them since, already told to the person:\n#{lines.join("\n")}"
  end
end
