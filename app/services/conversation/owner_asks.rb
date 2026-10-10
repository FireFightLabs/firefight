# Asking whoever started something before Halon stops or removes it (Chat::OwnerAsk). The owner is read from the
# provider when Halon pauses on the call, named on the confirmation, and asked in a direct message once the person
# confirms. Only their answer lets the call go on to the usual approval, and a no is what Halon is told.
module Conversation::OwnerAsks
  # Read when the turn pauses on a call that stops something, through the pack of the connection it reaches. Recorded in
  # the activity log as a read the call made. nil when the provider does not say who, or it is the person asking.
  def self.look_up!(agent_run, call_id:, tool:, environment_entry:, arguments:)
    chat = agent_run.chat
    existing = Chat::OwnerAsk.for_call(chat, call_id)
    return existing if existing

    owner = read_owner(agent_run, tool, environment_entry, arguments)
    return unless owner

    member = owner.member_in(agent_run.workspace)
    return if member && member == agent_run.acting_principal

    reachable = member && member.platform_user_id.present?
    Chat::OwnerAsk.create!(
      chat: chat, workspace: agent_run.workspace, tool_call_id: call_id.to_s, tool_name: tool.name, owner: (member if reachable),
      owner_name: member&.display_name || owner.name, owner_role: owner.role, what: owner.what,
      status: reachable ? Chat::OwnerAsk::STATUS_PENDING : Chat::OwnerAsk::STATUS_UNREACHABLE
    )
  rescue ActiveRecord::RecordNotUnique
    Chat::OwnerAsk.for_call(chat, call_id)
  end

  def self.read_owner(agent_run, tool, environment_entry, arguments)
    integration = tool.integration
    pack = Integrations::NativePack.for(integration.provider)
    return unless pack

    tool.read_before_asking!(agent_run.acting_principal, arguments, "who started it", incident_id: agent_run.incident&.id) do
      Integrations::NativePack.fetch!(integration).owner_of(tool.name, environment_row: integration.resolve_environment(environment_entry&.id), arguments: arguments)
    end
  rescue Integrations::Error, Integration::UnknownEnvironment => error
    Rails.logger.warn({ event: "owner_ask.unread", tool: tool.action_key, error: error.class.name }.to_json)
    nil
  end
  private_class_method :read_owner

  # The person confirmed the call, so its owner is asked now and the call waits for them. Returns whether it waits.
  # plan is the scheduled plan whose run asked, carried on once the owner answers.
  def self.ask!(chat, tool_call_id, by:, plan: nil)
    ask = Chat::OwnerAsk.for_call(chat, tool_call_id)
    return false unless ask&.pending?
    return false unless chat.await_owner!(tool_call_id)

    ask.move!(from: Chat::OwnerAsk::STATUS_PENDING, to: Chat::OwnerAsk::STATUS_ASKED, confirmed_by_id: by&.id, asked_at: Time.current, plan_id: plan&.id)
    OwnerAskJob.perform_later(ask.id)
    Conversation::LiveDelivery.safeguard_moved(ask.conversation)
    true
  end

  # The direct message to the owner, kept so it can be redrawn once answered.
  def self.deliver!(ask)
    return unless ask.asked? && ask.owner&.platform_user_id.present?

    posted = WorkspaceAdapter.for(ask.workspace).post_owner_ask(user_id: ask.owner.platform_user_id, ask: shown(ask))
    ask.update_columns(message_channel_id: posted[:channel_id], message_id: posted[:message_id]) if posted.is_a?(Hash)
  rescue AdapterError => error
    Rails.logger.warn({ event: "owner_ask.undelivered", owner_ask_id: ask.id, error: error.class.name }.to_json)
  end

  Shown = Data.define(:id, :status, :owner_name, :asker_name, :headline, :reason, :answered_words)

  def self.shown(ask)
    confirmed = ask.confirmed_by&.display_name || "Someone"
    call = ask.chat.tool_calls.find_by(tool_call_id: ask.tool_call_id)
    Shown.new(id: ask.id, status: ask.status, owner_name: ask.owner_name, asker_name: confirmed,
              headline: "#{confirmed} asked Halon to #{ask.tool_name.to_s.tr('_', ' ')} #{ask.what}, which you #{ask.owner_role}.",
              reason: (Chat::Tools.intent_of(call.arguments) if call), answered_words: answered_words(ask))
  end

  def self.answered_words(ask)
    case ask.status
    when Chat::OwnerAsk::STATUS_AGREED then "#{ask.owner_name} agreed."
    when Chat::OwnerAsk::STATUS_DECLINED then "#{ask.owner_name} said no, so it will not run."
    when Chat::OwnerAsk::STATUS_WITHDRAWN then "No longer needed. It was not run."
    end
  end

  # The owner's answer. Either way the call goes on, and a no reaches Halon as the call's refusal. The turn carries on
  # once nothing else in it waits. Returns why it was not taken, or nil.
  def self.answer!(ask, agreed:, by:)
    blocked = ask.answer_blocked_reason(by)
    return blocked if blocked

    status = agreed ? Chat::OwnerAsk::STATUS_AGREED : Chat::OwnerAsk::STATUS_DECLINED
    return "This was already answered." unless ask.move!(from: Chat::OwnerAsk::STATUS_ASKED, to: status, answered_at: Time.current)

    resume(ask)
    redraw(ask)
    nil
  end

  def self.resume(ask)
    conversation = ask.conversation
    chat = ask.chat
    resumed = conversation.with_lock do
      chat.owner_answered!(ask.tool_call_id) && chat.undecided.none?
    end
    Conversation::LiveDelivery.safeguard_moved(conversation)
    return unless resumed && ask.confirmed_by

    conversation.expect_reply!
    plan = ask.plan
    # A scheduled plan's run carries on as it was, with the changes the person approved ahead.
    if plan&.active?
      ConversationReplyJob.perform_later(conversation.id, ask.confirmed_by_id, nil, nil, nil, nil, plan.id, Conversation::Plans::MOVE_RUN)
    else
      ConversationReplyJob.perform_later(conversation.id, ask.confirmed_by_id)
    end
  end
  private_class_method :resume

  # The person moved on before the owner answered, so the call was withdrawn and the owner's message says so.
  def self.withdraw!(chat, tool_call_ids)
    Chat::OwnerAsk.where(chat: chat, tool_call_id: tool_call_ids, status: [ Chat::OwnerAsk::STATUS_ASKED, Chat::OwnerAsk::STATUS_PENDING ]).find_each do |ask|
      redraw(ask) if ask.move!(from: [ Chat::OwnerAsk::STATUS_ASKED, Chat::OwnerAsk::STATUS_PENDING ], to: Chat::OwnerAsk::STATUS_WITHDRAWN)
    end
  end

  def self.redraw(ask)
    return if ask.message_id.blank?

    WorkspaceAdapter.for(ask.workspace).update_owner_ask(channel_id: ask.message_channel_id, message_id: ask.message_id, ask: shown(ask))
  rescue AdapterError => error
    Rails.logger.warn({ event: "owner_ask.redraw_failed", owner_ask_id: ask.id, error: error.class.name }.to_json)
  end
  private_class_method :redraw
end
