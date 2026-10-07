# One capability, such as search_logs or rollback, for anything on the resource map. It finds the connection that holds
# the resource and runs that provider's own tool through Connection, so the call is authorized, approved, ledgered and
# replayed as the provider's action. A refusal comes back as a result the agent works around, never an exception.
class Chat::Tools::Capability < RubyLLM::Tool
  # tools are every one that could answer, callable the ones this agent may run, which is where a call is routed.
  def initialize(agent_run, spec, tools, callable: tools)
    super()
    @agent_run = agent_run
    @spec = spec
    @tools = tools
    @callable = callable
  end

  def name = @spec.tool_name

  def description = @spec.description

  def parameters_schema
    schema = Integrations::Capabilities.schema(@spec, Integrations::Capabilities.connection_choices(@agent_run.workspace, @spec, @tools))
    requires_approval? ? Chat::Tools.with_intent(schema) : schema
  end

  # A read is written by Firefight and only ever reads, so it never waits for the person. A change asks whenever the
  # tool it could run as would.
  def requires_approval?
    @spec.writes && @tools.any? { |tool| @agent_run.confirms?(tool.ability_action, tool_name: name) }
  end

  # A change whose words name another connection than the one it would run through is refused rather than put to the
  # person (Chat::Tools::Target).
  def approval_resolver = Chat::Tools::Target.resolver(@agent_run) { |given| misdirection(given).present? }

  # The call that gave the answer the last call ended on, the platform's when it answered for an observability tool, and
  # what it answered. nil when nothing answered.
  Answered = Data.define(:call, :result)
  attr_reader :answered

  def call(tool_call: nil, **arguments)
    @answered = nil
    return refused(tool_call, "#{name} changes things, so it is not used while investigating. It belongs in the fix.") if @spec.writes && @agent_run.reads_only?

    asked = arguments.transform_keys(&:to_s)
    given = asked.except(Chat::Tools::INTENT_ARG)
    return everywhere(given, tool_call) if given[Integrations::Capabilities::CONNECTION_ARG] == Integrations::Capabilities::ALL

    found = Integrations::Capabilities.resolve(@agent_run.workspace, @spec.key, given, @callable, principal: @agent_run.acting_principal)
    if @spec.writes
      refusal = misdirection(asked, found) || Chat::Tools::Target.drift(@agent_run, tool_call&.id, Chat::Tools::Target.describe(@agent_run, name, given))
      return refused(tool_call, refusal) if refusal
    end
    return ask(found, tool_call) unless found.fallback

    asked = connection(found)
    text = ask(found, tool_call, alone: false, asked: asked)
    return text if asked.waiting? || (!asked.failed? && Integrations::Capabilities.definitive?(asked.last_result))

    "#{Integrations::Capabilities.fell_back(found, failure: (text if asked.failed?))}\n#{ask(found.fallback, tool_call)}"
  rescue Integrations::Capabilities::Unroutable => error
    refused(tool_call, error.message)
  end

  private

  # A change only, since only a change carries words for the person. found is the call already routed, when there is one.
  def misdirection(asked, found = nil)
    return unless @spec.writes

    found ||= Integrations::Capabilities.resolve(@agent_run.workspace, @spec.key, asked.except(Chat::Tools::INTENT_ARG), @callable,
                                                 principal: @agent_run.acting_principal)
    Chat::Tools::Target.misdirection(found.tool.integration, Chat::Tools.intent_of(asked), called: "#{name} of #{found.resource.name}") do |other|
      label = Integrations::Capabilities.connections(other.tools.to_a).first || other.slug
      "To reach #{other.target_label}, name the resource by its id on the map there, or pass connection #{label}."
    end
  rescue Integrations::Capabilities::Unroutable
    nil
  end

  def connection(found) = Chat::Tools::Connection.new(@agent_run, found.tool)

  def ask(found, tool_call, alone: true, asked: connection(found))
    text = asked.run(found.arguments, environment_entry: found.environment_entry, tool_call_id: tool_call&.id, shown_as: name, present: found.present,
                                      alone: alone, target: target_of(found))
    @answered = Answered.new(call: found, result: asked.last_result) unless asked.failed? || asked.waiting?
    text
  end

  # Every connection that can answer, one after another, each answer headed with where it came from. Each call is its
  # own step in the ledger, as the provider's own action. The card reads failed only when none of them answered.
  def everywhere(given, tool_call)
    answered = false
    answers = Integrations::Capabilities.resolve_all(@agent_run.workspace, @spec.key, given, @callable, principal: @agent_run.acting_principal).map do |found|
      next Integrations::Capabilities.headed(found.environment_row, found.reason) if found.is_a?(Integrations::Capabilities::Refused)

      asked = connection(found)
      text = asked.run(found.arguments, environment_entry: found.environment_entry, tool_call_id: tool_call&.id, shown_as: name,
                                        present: found.present, alone: false, target: target_of(found))
      answered ||= !asked.failed?
      Integrations::Capabilities.headed(found.environment_row, text)
    end
    Chat::Tools.mark_failed(@agent_run, tool_call&.id) unless answered
    answers.join("\n\n")
  end

  # The resource and the connection it was routed to, as a person confirming the call reads it.
  def target_of(found)
    resource = found.resource
    where = found.environment_row ? found.tool.integration.target_label(found.environment_row) : found.tool.integration.target_label
    resource ? "#{resource.kind.humanize(capitalize: false)} #{resource.name} on #{where}" : where
  end

  def refused(tool_call, text)
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    text
  end
end
