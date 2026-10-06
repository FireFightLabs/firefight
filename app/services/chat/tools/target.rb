# What a call that changes something reaches, worked out from the tool and its arguments, never from the agent's words.
# A person confirming a call is shown this, and a call whose words name another connection than the one it reaches is
# refused before anyone is asked.
module Chat::Tools::Target
  # The connection tool the agent calls by name, in this workspace, or nil.
  def self.connection_tool(workspace, tool_name)
    name = tool_name.to_s
    workspace.integrations.where(deleted_at: nil).to_a.select { |integration| name.start_with?("#{integration.slug}_") }
             .sort_by { |integration| -integration.slug.length }.each do |integration|
      tool = integration.tools.find { |each| each.model_facing_name == name }
      return tool if tool
    end
    nil
  end

  def self.capability_spec(tool_name) = Integrations::Capabilities::SPECS.values.find { |spec| spec.tool_name == tool_name.to_s }

  # What a call reaches, such as "Faylee (Northflank), project faylee", or for a capability the resource it was routed
  # to, such as "service web on Faylee (Northflank), project faylee". nil for Firefight's own tools and for a call that
  # cannot be routed, which the call itself then refuses.
  def self.describe(agent_run, tool_name, arguments)
    given = arguments.to_h.stringify_keys
    tool = connection_tool(agent_run.workspace, tool_name)
    return connection_label(tool, given) if tool

    call = routed(agent_run, tool_name, given)
    "#{call.resource.kind.humanize(capitalize: false)} #{call.resource.name} on #{call.environment_row.integration.target_label(call.environment_row)}" if call
  end

  def self.connection_label(tool, given)
    integration = tool.integration
    environment_row = integration.resolve_environment(integration.environment_entry_for(given[Integration::Tool::ENVIRONMENT_ARG])&.id)
    integration.target_label(environment_row)
  rescue Integration::UnknownEnvironment
    integration.target_label
  end

  # The connection a capability that changes something would run through. A read never waits for the person.
  def self.routed(agent_run, tool_name, given)
    spec = capability_spec(tool_name)
    return unless spec&.writes

    Integrations::Capabilities.resolve(agent_run.workspace, spec.key, given.except(Chat::Tools::INTENT_ARG), principal: agent_run.acting_principal)
  rescue Integrations::Capabilities::Unroutable
    nil
  end

  # Why a call through integration, whose words say intent, is refused before it runs or is put to anyone. The words
  # name another connection to the same provider, by its name or what it reaches, and nothing that is this one's own.
  # nil when they do not, or there are no words. called is the tool as the agent named it, and hint says how to reach
  # the other connection instead.
  def self.misdirection(integration, intent, called:)
    return if intent.blank?

    provider_words = [ integration.provider, IntegrationProvider.find(integration.provider)&.name ].compact.map { |word| word.to_s.downcase }
    others = integration.workspace.integrations.where(deleted_at: nil, provider: integration.provider).where.not(id: integration.id).to_a
    return if others.empty?

    own = integration.naming_terms - provider_words
    their = others.to_h { |other| [ other, other.naming_terms - provider_words ] }
    shared = their.values.flatten
    distinct = own - shared
    return if distinct.any? { |term| mentions?(intent, term) }

    named = their.find { |_other, terms| (terms - own).any? { |term| mentions?(intent, term) } }&.first
    return unless named

    "Not run, and nobody was asked. #{called} reaches #{integration.target_label}, but what you wrote names #{named.display_name}. " \
      "#{yield(named)} Never call one connection's tool for another's account."
  end

  def self.mentions?(text, term) = text.match?(/(?<![[:alnum:]])#{Regexp.escape(term)}(?![[:alnum:]])/i)

  # How to reach other with the same tool, or why it cannot be reached.
  def self.reach_instead(other, handle)
    tool = other.tools.find_by(name: handle)
    return "#{other.display_name} has no #{handle} tool, so it cannot be reached this way. Tell the person." unless tool&.available?
    unless tool.enabled? && other.operational?
      return "#{other.display_name}'s #{handle} tool is switched off, so it cannot be reached until an admin switches it on in " \
             "Integrations. Tell the person, and open the tools again once they say it is on."
    end

    "To reach #{other.target_label}, call #{tool.model_facing_name}, opening its group with open_tools if you do not hold it."
  end

  # The person was shown one target and confirmed it. If the call now reaches another, since a connection or the map
  # changed in between, it is not run. nil when it is the same, or nothing was recorded.
  def self.drift(agent_run, tool_call_id, current)
    return if tool_call_id.blank?

    shown = agent_run.chat&.tool_calls&.where(tool_call_id: tool_call_id)&.pick(:target)
    return if shown.blank? || shown == current

    "Not run. The person confirmed this for #{shown}, but it now reaches #{current || 'nothing it can name'}, since what it " \
      "runs through changed. Tell them, and ask again if it should still be done."
  end

  # A call RubyLLM would pause for the person runs at once when it is refused, so the refusal reaches the agent and
  # nobody is asked to confirm a call that will not run. Otherwise the decision is the one recorded on the call, as
  # RubyLLM reads it when a tool has no resolver of its own.
  def self.resolver(agent_run)
    lambda do |tool_call|
      next true if yield(tool_call.arguments.to_h.stringify_keys)

      case agent_run.chat&.tool_calls&.where(tool_call_id: tool_call.id)&.pick(:approval)
      when Chat::APPROVAL_APPROVED then true
      when Chat::APPROVAL_DENIED then false
      end
    end
  end

  # What each call waiting for the person reaches, kept with it when it is asked, so the question names it and the call
  # is checked against it when it runs.
  def self.record!(agent_run, tool_calls)
    tool_calls.each do |tool_call|
      label = describe(agent_run, tool_call.name, tool_call.arguments)
      tool_call.update_columns(target: label) if label
    end
  end
end
