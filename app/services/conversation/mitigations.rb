# Changes customers feel for a while (Chat::Mitigation): proposed when Halon pauses on one, started when it runs, its undo
# written from what it returned, a reminder before it runs out, and its undo run when it does, unless someone kept it.
# The undo runs as whoever asked for the change, through the same tools and the gateway, so grants, approval rules and
# the activity log apply as for any call.
module Conversation::Mitigations
  KIND_REMINDER = "reminder".freeze
  KIND_ENDED = "ended".freeze
  KIND_KEPT = "kept".freeze
  KIND_EXTENDED = "extended".freeze

  # What a person or the platform is shown, the same on the dashboard and in Slack.
  Notice = Data.define(:id, :kind, :title, :text, :live, :conversation_id)

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
    step = running_plan_step(mitigation.chat)
    # A step of a plan's undo puts something back, so it is never itself counted down and undone.
    if step&.plan&.undo?
      mitigation.move!(from: Chat::Mitigation::STATUS_PROPOSED, to: Chat::Mitigation::STATUS_CANCELLED)
      return nil
    end
    return nil unless mitigation.start!(result: result_text(result))

    mitigation.update_columns(plan_step_id: step.id) if step

    MitigationUndoJob.perform_later(mitigation.id)
    Conversation::LiveDelivery.safeguard_moved(mitigation.conversation)
    started_note(mitigation)
  end

  # The change step of a plan in progress in this chat that is running now, which this call is carrying out.
  def self.running_plan_step(chat)
    Chat::Plan::Step.joins(:plan).where(chat_plans: { chat_id: chat.id, status: Chat::Plan::STATUS_ACTIVE })
                    .where(kind: Chat::Plan::Step::KIND_CHANGE, status: Chat::Plan::Step::STATUS_RUNNING).order(:updated_at).last
  end
  private_class_method :running_plan_step

  # Undo was pressed on a plan, so a change its steps made that is still in place is put back by the plan's undo, and
  # Firefight stops counting it down, so nothing is undone twice.
  def self.handed_to_plan!(plan)
    Chat::Mitigation.where(plan_step_id: plan.steps.select(:id), status: [ Chat::Mitigation::STATUS_ACTIVE, Chat::Mitigation::STATUS_KEPT ])
                    .update_all(status: Chat::Mitigation::STATUS_WITH_PLAN, outcome: "Put back by the plan's undo instead.", ended_at: Time.current,
                                told_at: Time.current, updated_at: Time.current)
    Conversation::LiveDelivery.safeguard_moved(plan.conversation)
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

  # Written by Halon from what the change returned, such as the id of a rule it made, and checked against what the
  # workspace can run, as a fix's undo is (Investigation::UndoWriter). A step only a person can do leaves it by hand.
  def self.write_undo!(mitigation)
    workspace = mitigation.workspace
    step = FirefightAi::UndoWriter::Step.new(
      position: 1, kind: Investigation::RemediationStep::KIND_ACTION, description: mitigation.title, repository: nil, tool: mitigation.tool_name,
      arguments: mitigation.arguments.presence, result: mitigation.result, undo: nil, status: Investigation::RemediationStep::STATUS_DONE
    )
    plan = FirefightAi::UndoWriter.new(workspace).write([ step ], summary: mitigation.title, tools: undo_tools(workspace), inferable: mitigation.conversation)
    steps = plan["steps"].each_with_index.map do |asked, index|
      Investigation::RemediationStep.checked(workspace, asked, position: index + 1, principal: mitigation.asker)
    end
    by_hand = steps.reject(&:action?)
    if steps.empty? || by_hand.any?
      words = by_hand.map { |each| [ each.description, each.missing ].compact.join(" ") }.join(" ").presence || "Nothing it was given says how."
      return written!(mitigation, Chat::Mitigation::UNDO_BY_HAND, [], "Undo it by hand: #{words}")
    end

    written!(mitigation, Chat::Mitigation::UNDO_READY, steps.map { |each| { "description" => each.description, "action_key" => each.action_key, "arguments" => each.arguments } },
             steps.map(&:description).join(" "))
  rescue Investigation::RemediationPlan::Refused => refused
    written!(mitigation, Chat::Mitigation::UNDO_BY_HAND, [], "Undo it by hand, since Halon's undo could not run here: #{refused.message}")
  rescue FirefightAi::OutOfCredit
    written!(mitigation, Chat::Mitigation::UNDO_BY_HAND, [], AiCredit.cannot(workspace, "write how to undo this"))
  rescue FirefightAi::Error => error
    Rails.logger.warn({ event: "mitigation.undo_not_written", mitigation_id: mitigation.id, error: error.class.name }.to_json)
    written!(mitigation, Chat::Mitigation::UNDO_BY_HAND, [], "Halon could not reach its AI to write how to undo this, so undo it by hand.")
  end

  def self.written!(mitigation, state, steps, note)
    mitigation.update!(undo_state: state, undo_steps: steps, undo_note: Chat::SecretFree.redacted(note))
    Conversation::LiveDelivery.safeguard_moved(mitigation.conversation)
  end
  private_class_method :written!

  # Every tool that changes something here, by the name Halon calls it, and the capabilities that change things.
  def self.undo_tools(workspace)
    connected = Integration::Tool.in_workspace(workspace).reject(&:read_only).map(&:model_facing_name)
    capabilities = Integrations::Capabilities.offered(workspace).filter_map { |spec, _tools| spec.tool_name if spec.writes }
    connected + capabilities
  end

  # Due within REMIND_BEFORE, said once.
  def self.remind!(mitigation)
    return unless mitigation.claim_reminder!

    left = Chat::Mitigation.duration_words(((mitigation.expires_at - Time.current) / 60).ceil.clamp(1, nil))
    how = mitigation.undo_state == Chat::Mitigation::UNDO_BY_HAND ? "It is then due to be undone by hand. #{mitigation.undo_note}" : "Firefight then undoes it."
    tell!(mitigation, KIND_REMINDER, "#{mitigation.title} ends in about #{left}. #{how} Keep it or extend it if it is still needed.")
  end

  # Run out and not kept: the undo runs, or a person is told it is due by hand.
  def self.expire!(mitigation)
    return unless mitigation.move!(from: Chat::Mitigation::STATUS_ACTIVE, to: Chat::Mitigation::STATUS_UNDOING, claimed_at: Time.current)

    undo!(mitigation, by: nil)
  end

  # Undo now, pressed by a person. Returns why it was not undone, or nil.
  def self.undo_now!(mitigation, by:)
    blocked = mitigation.undo_blocked_reason(by)
    return blocked if blocked
    return "This was just changed by someone else." unless mitigation.move!(from: [ Chat::Mitigation::STATUS_ACTIVE, Chat::Mitigation::STATUS_KEPT ],
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

  def self.run_step(turn, mitigation, step)
    tool = Integration::Tool.in_workspace(mitigation.workspace).find { |each| each.action_key == step["action_key"] }
    return [ :failed, "the tool it runs with is switched off or gone" ] unless tool

    arguments = step["arguments"].to_h
    entry = tool.integration.environment_entry_for(arguments[Integration::Tool::ENVIRONMENT_ARG])
    connection = Chat::Tools::Connection.new(turn, tool)
    said = connection.run(arguments.except(Integration::Tool::ENVIRONMENT_ARG), environment_entry: entry, tool_call_id: nil, shown_as: tool.model_facing_name)
    return :held if connection.waiting?
    return [ :failed, said.to_s.lines.first.to_s.strip.truncate(300) ] if connection.failed?

    :ran
  rescue Integration::UnknownEnvironment => error
    [ :failed, error.message ]
  end
  private_class_method :run_step

  def self.outcome_words(mitigation, outcome, step, _by)
    return "Undoing #{mitigation.title} needs an approval, so it waits in the chat for someone to approve it and then for Run." if outcome == :held

    "Firefight could not undo #{mitigation.title} at the step \"#{step['description']}\": #{outcome.last}. Undo it by hand."
  end
  private_class_method :outcome_words

  def self.ending!(mitigation, status, text)
    mitigation.move!(from: Chat::Mitigation::STATUS_UNDOING, to: status, ended_at: Time.current, outcome: Chat::SecretFree.redacted(text))
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
    unless user_id.blank? || (in_thread && adapter.direct_conversation?(channel_id: conversation.channel_id))
      posted = post(mitigation) { adapter.post_mitigation_notice_to_user(user_id: user_id, notice: notice) } || posted
    end
    mitigation.update_columns(message_channel_id: posted[:channel_id], message_id: posted[:message_id]) if posted.is_a?(Hash) && posted[:message_id]
    notice
  end

  def self.notice(mitigation, kind, text)
    Notice.new(id: mitigation.id, kind: kind, title: mitigation.title, text: text, live: mitigation.active? || mitigation.kept?,
               conversation_id: (mitigation.conversation.id if mitigation.conversation.personal?))
  end

  def self.post(mitigation)
    yield
  rescue AdapterError => error
    Rails.logger.warn({ event: "mitigation.untold", mitigation_id: mitigation.id, error: error.class.name }.to_json)
    nil
  end
  private_class_method :post

  # Pressed on a message the platform shows: the message is redrawn so it no longer offers what is done. Returns why
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
    "Temporary changes you made earlier, and what became of them since, already told to the person:\n#{lines.join("\n")}"
  end
end
