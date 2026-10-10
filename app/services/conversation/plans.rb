# The plans Halon keeps in a chat, from what a person presses on one to telling the chat and its platform it moved. A
# scheduled plan runs as the person who approved it, once a fresh reading says nothing moved in between and no freeze
# covers the time.
module Conversation::Plans
  # Why a turn was started for a plan, which says what Halon is told at its start.
  MOVE_RUN = "run"
  MOVE_RETRY = "retry"
  MOVE_UNDO = "undo"
  MOVES = [ MOVE_RUN, MOVE_RETRY, MOVE_UNDO ].freeze

  # Said on the plan when the scheduled run did not start, with the reading or the freeze that stopped it.
  NOT_RUN = "Nothing ran.".freeze
  COULD_NOT_CHECK = "Halon could not read how things stand now, so it did not start without someone looking first.".freeze

  # What Halon is told about the plans in play, at the start of every turn.
  def self.for_halon(chat)
    plans = chat.plans.open.includes(:steps, :approved_by).order(:created_at).to_a
    return nil if plans.empty?

    "Your plans in this chat. Carry each to its goal, and update it with update_plan as each step starts and ends:\n" \
      "#{plans.map { |plan| described(plan) }.join("\n")}"
  end

  # A plan as Halon reads it, every step with how it stands, its undo and what it said.
  def self.described(plan)
    head = "Plan #{plan.id} (#{plan.status_words}#{", runs #{plan.run_at_words}" if plan.run_at && plan.status != Chat::Plan::STATUS_ACTIVE}" \
           "#{", approved by #{plan.approved_by.display_name}" if plan.approved_by}): #{plan.goal}"
    lines = plan.steps.map do |step|
      [ "  #{step.position}. [#{step.words}] #{step.kind}#{" in #{step.place}" if step.place}: #{step.description}",
        (" Tool: #{step.tool}." if step.tool), (" Undo: #{step.undo}" if step.undo), (" Said: #{step.note}" if step.note),
        (" Verdict: #{step.verdict}." if step.verdict) ].compact.join
    end
    [ head, *lines, ("  Stopped: #{plan.stop_reason}" if plan.stopped? && plan.stop_reason) ].compact.join("\n")
  end

  # The time zone a scheduled plan's time is read in when Halon was not told one, which is the person's own as their
  # chat platform has it. nil when it does not say.
  def self.time_zone_of(member, workspace)
    user_id = member.try(:platform_user_id)
    return nil if user_id.blank?

    zone = WorkspaceAdapter.for(workspace).get_user_info(user_id: user_id)[:timezone]
    zone if ActiveSupport::TimeZone[zone.to_s]
  rescue AdapterError
    nil
  end

  # The tools whose answer is a reading of how something stands, which a check after a change needs.
  def self.reading_names(workspace)
    Integrations::Capabilities::SPECS.values.reject(&:writes).map(&:tool_name) +
      [ ResourceMap::KeyQueries::TOOL_NAME, Chat::Tools::LogPatterns::NAME ] + workspace.reading_tool_names.to_a
  end

  def self.read_since?(chat, time)
    chat.tool_calls.where(created_at: time.., failed: false, name: reading_names(chat.workspace)).exists?
  end

  # The chat's page looks again, and the platform's message is posted or redrawn.
  def self.moved!(plan)
    conversation = plan.conversation
    return unless conversation.is_a?(Conversation)

    Conversation::LiveDelivery.plan_moved(conversation)
    ChatPlanMessageJob.perform_later(plan.id) if posted?(plan)
  end

  # A chat in a thread shows its plans there. A dashboard chat's plan goes to its person once it has a time they
  # approved, since it runs when they may not be looking.
  def self.posted?(plan)
    conversation = plan.conversation
    return false if conversation.mcp?

    conversation.thread_id.present? || plan.message_id.present? || (plan.approved_by_id.present? && conversation.started_by.try(:platform_user_id).present?)
  end

  def self.approve!(plan, by:)
    blocked = plan.approve_blocked_reason(by)
    return blocked if blocked
    return plan.reload.approve_blocked_reason(by) || "This plan is not waiting to be scheduled." unless plan.approve!(by: by)

    moved!(plan)
    nil
  end

  def self.cancel!(plan, by:)
    blocked = plan.cancel_blocked_reason(by)
    return blocked if blocked
    return "This plan has already ended." unless plan.cancel!(reason: "#{by.display_name} cancelled it.")

    moved!(plan)
    nil
  end

  # The next turn, as whoever pressed it, starts again from where it stopped.
  def self.retry!(plan, by:)
    blocked = plan.retry_blocked_reason(by)
    return blocked if blocked
    return "Only a plan that stopped can be tried again." unless plan.resume!

    hand_to_halon(plan, by, MOVE_RETRY)
    moved!(plan)
    nil
  end

  # The undo is made at once from the undo each change was written with, and the next turn, as whoever pressed it,
  # carries it out. Each change still asks as any change does.
  def self.undo!(plan, by:)
    blocked = plan.undo_blocked_reason(by)
    return blocked if blocked
    return "Its undo is already under way." unless plan.claim_undo!

    begin
      undo = Chat::Plan.make!(chat: plan.chat, made_by: by, goal: "Undo: #{plan.goal}", steps: plan.undo_steps, undoes: plan)
    rescue Chat::Plan::Refused => refused
      plan.update_columns(undo_requested_at: nil)
      return "Halon could not make the undo. #{refused.message}"
    end
    # A stopped plan being undone is over, so Halon never carries it on beside its undo.
    plan.cancel!(reason: "#{by.display_name} pressed Undo.") if plan.stopped?
    hand_to_halon(undo, by, MOVE_UNDO)
    moved!(plan)
    moved!(undo)
    nil
  end

  # From ChatPlanRunJob once the plan's time came. A freeze or a reading that says things moved stops it before anything
  # runs. It stays scheduled while Halon reads, so a worker lost on the way leaves it for the next sweep, and the claim
  # hands it to Halon once.
  def self.run_scheduled!(plan, now: Time.current)
    return unless plan.scheduled? && plan.run_at <= now

    window = Workspace::FreezeWindows.covering(plan.workspace, now)
    return stopped!(plan, "#{Workspace::FreezeWindows.sentence(window, plan.time_zone)} #{NOT_RUN}") if window

    unavailable = Investigation.unavailable_reason(plan.workspace)
    return stopped!(plan, "#{unavailable} #{NOT_RUN}") if unavailable

    report = Chat::StateCheck.run(
      owner: plan, workspace: plan.workspace, principal: plan.approved_by, source: AbilityGateway::SOURCE_CONVERSATION,
      call: Chat::StateCheck::Call.new(named: "the plan to #{plan.goal}", asked: plan.steps.map { |step| [ "Step #{step.position}", step.description ] },
                                       approved_by: plan.approved_by&.display_name || "Someone")
    )
    plan.checked!(report)
    return stopped!(plan, [ report.warning || COULD_NOT_CHECK, report.state, NOT_RUN ].compact.join(" ")) unless report.change == Chat::CurrentState::UNCHANGED
    return unless plan.claim_run!(now)

    hand_to_halon(plan, plan.approved_by, MOVE_RUN)
    moved!(plan)
  end

  def self.stopped!(plan, reason)
    moved!(plan) if plan.stop!(reason)
  end
  private_class_method :stopped!

  def self.hand_to_halon(plan, by, move)
    conversation = plan.conversation
    conversation.expect_reply!
    ConversationReplyJob.perform_later(conversation.id, by.id, nil, nil, nil, nil, plan.id, move)
  end
  private_class_method :hand_to_halon

  # What Halon reads at the start of the turn a plan was handed to it for.
  def self.note(plan, move, by)
    who = by.try(:display_name) || "The person"
    case move
    when MOVE_RUN
      tools = plan.approved_tools
      "It is now the time #{who} approved for the plan to #{plan.goal} (plan #{plan.id}). Halon read how things stand just now: " \
        "#{plan.state_now.presence || 'nothing to report'}. Carry it out step by step, updating the plan as you go. #{who} approved its " \
        "changes ahead, so #{tools.any? ? "#{tools.uniq.to_sentence} run without asking again" : 'they ask as usual'}. Approval rules still apply. " \
        "End with the check and a report."
    when MOVE_RETRY
      "#{who} pressed Retry on the plan to #{plan.goal} (plan #{plan.id}). #{plan.standing} Read how things stand now first, then " \
        "carry on from the step that failed, updating the plan as you go."
    else
      "#{who} pressed Undo on the plan to #{plan.undoes&.goal} (plan #{plan.undoes_id}). The undo is plan #{plan.id}, made from the undo each " \
        "change was written with. Carry it out step by step, updating it as you go, and end with its check and a report."
    end
  end

  # Posts the plan where its chat lives, or redraws it there. From ChatPlanMessageJob, one at a time per plan.
  def self.tell!(plan)
    adapter = WorkspaceAdapter.for(plan.workspace)
    conversation = plan.conversation
    direct = conversation.thread_id.blank?
    chat_id = (conversation.id if conversation.personal?)
    if plan.message_id.present?
      adapter.update_chat_plan(channel_id: plan.message_channel_id, message_id: plan.message_id, plan: plan, direct: direct, conversation_id: chat_id)
      return
    end

    posted = if direct
      adapter.post_chat_plan_to_user(user_id: conversation.started_by.platform_user_id, plan: plan, conversation_id: chat_id)
    else
      adapter.post_chat_plan(channel_id: conversation.channel_id, thread_id: conversation.thread_id, plan: plan)
    end
    plan.update_columns(message_channel_id: posted[:channel_id], message_id: posted[:message_id]) if posted
  rescue AdapterError => error
    Rails.logger.warn({ event: "chat_plan.untold", plan_id: plan.id, error: error.class.name }.to_json)
  end
end
