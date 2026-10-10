# What runs around a chat's call that changes something beyond its risk, by what its action does
# (Ability::Action::EFFECTS): a statement that writes rows is counted and copied first and checked after
# (Chat::DataRepairs), a change customers feel starts its time once it ran (Conversation::Mitigations), and a call
# whose owner said no is not run (Conversation::OwnerAsks). call_id is the call the person confirmed.
class Chat::Safeguards
  # The safeguards a call has, or nil when it has none. A mitigation through a tool whose action is one is kept here
  # when it ran without a pause, such as one allowed for the rest of the chat.
  def self.around(agent_run, tool, call_id, environment_entry:, arguments:)
    chat = agent_run.chat
    return if chat.nil? || agent_run.reads_only? || call_id.blank?

    repair = (Chat::DataRepair.for_call(chat, call_id) if Chat::DataRepairs.applies?(agent_run, tool))
    ask = Chat::OwnerAsk.for_call(chat, call_id)
    mitigation = Chat::Mitigation.for_call(chat, call_id)
    if mitigation.nil? && Integrations::Mitigations.call?(tool, arguments)
      call = chat.tool_calls.find_by(tool_call_id: call_id)
      mitigation = Conversation::Mitigations.propose!(
        agent_run, call_id: call_id, tool: tool, environment_entry: environment_entry, arguments: arguments, tool_name: tool.model_facing_name,
        target: call&.target, intent: (Chat::Tools.intent_of(call.arguments) if call)
      )
    end
    return unless repair || ask || mitigation

    new(agent_run, tool, environment_entry, arguments, repair: repair, ask: ask, mitigation: mitigation)
  end

  # Settled when Halon pauses on calls, so the confirmation can say what each will touch, who started what it stops,
  # and when a change customers feel is undone.
  def self.prepare!(agent_run, tool_calls)
    tool_calls.each do |tool_call|
      found = resolve(agent_run, tool_call)
      next unless found

      action = found.tool.ability_action
      if action&.effect?(Ability::Action::EFFECT_STOPS)
        Conversation::OwnerAsks.look_up!(agent_run, call_id: tool_call.tool_call_id, tool: found.tool, environment_entry: found.environment_entry,
                                                    arguments: found.arguments)
        # A scheduled plan's change was approved ahead and nobody is there to confirm it, so its owner is asked at once.
        if agent_run.respond_to?(:approved_ahead?) && agent_run.approved_ahead?(tool_call.name)
          Conversation::OwnerAsks.ask!(agent_run.chat, tool_call.tool_call_id, by: agent_run.acting_principal)
        end
      end
      next unless found.mitigation

      Conversation::Mitigations.propose!(agent_run, call_id: tool_call.tool_call_id, tool: found.tool, environment_entry: found.environment_entry,
                                                    arguments: found.arguments, tool_name: tool_call.name, target: tool_call.try(:target),
                                                    intent: Chat::Tools.intent_of(tool_call.arguments))
    end
  end

  # A call through a connection tool or a capability that changes something, as the provider is sent it.
  Resolved = Data.define(:tool, :environment_entry, :arguments, :mitigation)

  def self.resolve(agent_run, tool_call)
    given = tool_call.arguments.to_h.stringify_keys
    tool = Chat::Tools::Target.connection_tool(agent_run.workspace, tool_call.name)
    if tool
      entry = tool.integration.environment_entry_for(given[Integration::Tool::ENVIRONMENT_ARG])
      arguments = Chat::DataRepairs.provider_arguments(tool, entry, given)
      return Resolved.new(tool: tool, environment_entry: entry, arguments: arguments, mitigation: Integrations::Mitigations.call?(tool, arguments))
    end

    call = Chat::Tools::Target.routed(agent_run, tool_call.name, given)
    call && capability(call, given)
  rescue Integration::UnknownEnvironment
    nil
  end
  private_class_method :resolve

  def self.capability(call, given)
    Resolved.new(tool: call.tool, environment_entry: call.environment_entry, arguments: call.arguments,
                 mitigation: Integrations::Mitigations.call?(call.tool, call.arguments) || scales_down?(call, given))
  end
  private_class_method :capability

  # A capability call that changes something, kept as a mitigation as it runs when it is one and nobody was asked, such
  # as one allowed for the rest of the chat. call is the routed Integrations::Capabilities::Call.
  def self.capability_call!(agent_run, call, tool_call_id, given)
    return if agent_run.chat.nil? || agent_run.reads_only? || tool_call_id.blank?

    found = capability(call, given)
    return unless found.mitigation

    record = agent_run.chat.tool_calls.find_by(tool_call_id: tool_call_id)
    Conversation::Mitigations.propose!(agent_run, call_id: tool_call_id, tool: found.tool, environment_entry: found.environment_entry,
                                                  arguments: found.arguments, tool_name: record&.name || call.spec.tool_name, target: record&.target,
                                                  intent: Chat::Tools.intent_of(given))
  end

  # Fewer instances than the map last read the resource running is a change customers feel, whichever provider runs
  # it. A resource whose count the map does not hold is not taken for one.
  def self.scales_down?(call, given)
    return false unless call.spec.key == Integrations::Capabilities::SCALE

    now = Integer(call.resource&.details.to_h["instances"].to_s, exception: false)
    asked = Integer(given["instances"].to_s, exception: false)
    !now.nil? && !asked.nil? && asked < now
  end
  private_class_method :scales_down?

  def initialize(agent_run, tool, environment_entry, arguments, repair:, ask:, mitigation:)
    @agent_run = agent_run
    @tool = tool
    @environment_entry = environment_entry
    @arguments = arguments
    @repair = repair
    @ask = ask
    @mitigation = mitigation
  end

  # Why the call must not run, or nil.
  def before
    return @ask.declined_words if @ask&.declined?

    Chat::DataRepairs.before_write(@agent_run, @repair, @tool, @environment_entry, @arguments) if @repair
  end

  # What Halon reads after the provider's answer, or nil.
  def after(ok:, result:)
    notes = []
    notes << Chat::DataRepairs.after_write(@agent_run, @repair, @tool, @environment_entry, @arguments, ok: ok) if @repair
    notes << Conversation::Mitigations.ran!(@mitigation, ok: ok, result: result) if @mitigation&.proposed?
    notes.compact.join(" ").presence
  end
end
