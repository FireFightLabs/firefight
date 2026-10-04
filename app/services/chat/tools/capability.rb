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
    schema = Integrations::Capabilities.schema(@spec, Integrations::Capabilities.connections(@tools))
    requires_approval? ? Chat::Tools.with_intent(schema) : schema
  end

  # A read is written by Firefight and only ever reads, so it never waits for the person. A change asks whenever the
  # tool it could run as would.
  def requires_approval?
    @spec.writes && @tools.any? { |tool| @agent_run.confirms?(tool.ability_action, tool_name: name) }
  end

  def call(tool_call: nil, **arguments)
    return refused(tool_call, "#{name} changes things, so it is not used while investigating. It belongs in the fix.") if @spec.writes && @agent_run.reads_only?

    given = arguments.transform_keys(&:to_s).except(Chat::Tools::INTENT_ARG)
    return everywhere(given, tool_call) if given[Integrations::Capabilities::CONNECTION_ARG] == Integrations::Capabilities::ALL

    found = Integrations::Capabilities.resolve(@agent_run.workspace, @spec.key, given, @callable)
    connection(found).run(found.arguments, environment_entry: found.environment_entry, tool_call_id: tool_call&.id, shown_as: name, present: found.present)
  rescue Integrations::Capabilities::Unroutable => error
    refused(tool_call, error.message)
  end

  private

  def connection(found) = Chat::Tools::Connection.new(@agent_run, found.tool)

  # Every connection that can answer, one after another, each answer headed with where it came from. Each call is its
  # own step in the ledger, as the provider's own action. The card reads failed only when none of them answered.
  def everywhere(given, tool_call)
    answered = false
    answers = Integrations::Capabilities.resolve_all(@agent_run.workspace, @spec.key, given, @callable).map do |found|
      next Integrations::Capabilities.headed(found.environment_row, found.reason) if found.is_a?(Integrations::Capabilities::Refused)

      asked = connection(found)
      text = asked.run(found.arguments, environment_entry: found.environment_entry, tool_call_id: tool_call&.id, shown_as: name,
                                        present: found.present, alone: false)
      answered ||= !asked.failed?
      Integrations::Capabilities.headed(found.environment_row, text)
    end
    Chat::Tools.mark_failed(@agent_run, tool_call&.id) unless answered
    answers.join("\n\n")
  end

  def refused(tool_call, text)
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    text
  end
end
