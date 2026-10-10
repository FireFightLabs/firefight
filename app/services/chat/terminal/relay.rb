# Takes the calls a command in Halon's terminal makes, through ff or a provider's own command line tool, and runs each as
# the tool Halon would have called, as the run that started the command, so permissions, approval rules, the read
# contract and the activity log apply exactly as to Halon's own call, and Firefight adds the key. A call that changes
# something goes through only when the person confirmed the command as a change, and never in an investigation.
class Chat::Terminal::Relay
  OUTCOME_OK = "ok".freeze
  OUTCOME_FAILED = "failed".freeze
  OUTCOME_REFUSED = "refused".freeze
  OUTCOME_WAITING = "waiting".freeze

  # What the relay answers: an outcome and the words for ff, or a status and a body for a provider's own tool.
  Said = Data.define(:outcome, :text)
  Answered = Data.define(:status, :body)

  # session is nil when only the listing is read, for the run that is about to start a command.
  def initialize(session, agent_run: session&.agent_run)
    @session = session
    @run = Caller.new(agent_run)
  end

  # The tools a command may call, a line each, those whose name or description holds every word of query.
  def tools(query = nil)
    words = query.to_s.downcase.split
    entries.values.select { |entry| words.all? { |word| "#{entry.name} #{entry.description}".downcase.include?(word) } }.map do |entry|
      { "name" => entry.name.to_s, "reads" => !change_possible?(entry), "description" => entry.description }
    end
  end

  def describe(name)
    entry = entries[name.to_s]
    return unless entry

    { "name" => entry.name.to_s, "description" => entry.tool.description.to_s, "parameters" => entry.tool.parameters_schema }
  end

  def call(name, arguments)
    entry = entries[name.to_s]
    return Said.new(outcome: OUTCOME_REFUSED, text: "No tool called #{name} can be called here. ff tools lists those that can.") unless entry

    given = arguments.to_h.stringify_keys
    refused = refusal(entry, given)
    return Said.new(outcome: OUTCOME_REFUSED, text: refused) if refused

    @run.reset!
    text = entry.tool.call(**given.deep_symbolize_keys)
    Said.new(outcome: outcome(entry, text), text: answer_text(entry, text))
  end

  # Each connection's own command line tool the run may use, pointed at this relay with token.
  def clis(token)
    connections = entries.values.filter_map { |entry| connection_tool(entry) if connection?(entry) }
    Integrations::Clis.offered(connections, base_url: "#{Chat::Terminal.relay_base}/#{Chat::Terminal::API_PATH}", token: token)
  end

  # One request a provider's own command line tool made, as the connection's relayed tool.
  def api(connection, verb, path, query, body)
    entry = cli_entry(connection)
    return Answered.new(status: 404, body: error("No command line tool reaches #{connection} through Firefight.")) unless entry

    tool = connection_tool(entry)
    cli = Integrations::Clis.for(tool.integration)
    arguments = cli.arguments(verb, path, query, body)
    refused = refusal(entry, arguments)
    return Answered.new(status: 403, body: error(refused)) if refused

    @run.reset!
    text = entry.tool.run(arguments, environment_entry: nil, tool_call_id: nil, relayed: true)
    relayed = entry.tool.last_result&.dig(Integrations::Telemetry::STRUCTURED, Integrations::Telemetry::RELAYED)
    return Answered.new(status: 200, body: cli.answer(relayed)) if relayed && !entry.tool.failed?

    status = outcome(entry, text) == OUTCOME_WAITING ? 409 : 502
    Answered.new(status: status, body: error(answer_text(entry, text)))
  rescue Integrations::Clis::Refused, Integration::UnknownEnvironment => refusal
    Answered.new(status: 403, body: error(refusal.message))
  end

  private

  # Ready for whoever the run acts for. Firefight's own tools only when they read, since a command never changes
  # Firefight itself, and Halon's own bookkeeping never.
  def entries
    @entries ||= Chat::Tools.catalog(@run).select { |entry| offered?(entry) }.index_by { |entry| entry.name.to_s }
  end

  def offered?(entry)
    return false unless entry.state == Chat::Tools::STATE_READY && entry.tool
    return false if Chat::Tools.internal_names.include?(entry.name.to_s)
    return true if connection?(entry) || capability?(entry)

    Chat::Tools.firefight_reading_names.include?(entry.name.to_s)
  end

  def connection?(entry) = entry.tool.is_a?(Chat::Tools::Connection)

  def capability?(entry) = entry.tool.is_a?(Chat::Tools::Capability)

  def connection_tool(entry) = @run.workspace.connection_tools_by_name[entry.name.to_s]

  def cli_entry(connection)
    entries.values.find do |entry|
      tool = connection?(entry) && connection_tool(entry)
      cli = tool && tool.integration.slug == connection.to_s && Integrations::Clis.for(tool.integration)
      cli && tool.name == cli::TOOL
    end
  end

  # Why the call is not made, or nil. A change needs the person's confirmation of the command, and a run that only
  # reads makes none.
  def refusal(entry, given)
    return Chat::TerminalSession::ENDED unless @session
    return Chat::TerminalSession::TOO_MANY unless @session.count_call!
    return unless change?(entry, given)
    return safeguarded(entry, given) if @session.changes_allowed

    why = if @session.owner.is_a?(Conversation)
      "The person did not confirm this command as a change. Run it again with changes true, so they are asked first."
    else
      "An investigation only reads, and a change belongs in its fix."
    end
    "#{entry.name} changes something, so it was not run. #{why}"
  end

  # A change with a safeguard of its own (Chat::Safeguards) is asked about call by call, with what it touches, so a command
  # never makes it. Halon calls the tool itself instead, and the person sees that call on its own.
  def safeguarded(entry, given)
    called = "#{entry.name} was not run from the command. Call it yourself, so the person is asked about this call on its own"
    return "#{called}, since a capability that changes something is confirmed with what it reaches." if capability?(entry)

    tool = connection_tool(entry)
    run = @session.agent_run
    environment_entry = tool.integration.environment_entry_for(given[Integration::Tool::ENVIRONMENT_ARG])
    arguments = Chat::DataRepairs.provider_arguments(tool, environment_entry, given)
    return "#{called}, since it writes rows, which are counted and copied first and checked after." if Chat::DataRepairs.applies?(run, tool)
    return "#{called}, since it stops something, and whoever started it is asked first." if tool.ability_action&.effect?(Ability::Action::EFFECT_STOPS)

    "#{called}, since customers feel it for a while and it is undone unless kept." if Integrations::Mitigations.call?(tool, arguments)
  rescue Integration::UnknownEnvironment => error
    error.message
  end

  def change?(entry, given)
    if connection?(entry)
      tool = connection_tool(entry)
      return !tool.read_only? && !Integrations::ReadGuards.reads?(tool, given)
    end

    capability?(entry) && Chat::Tools::Target.capability_spec(entry.name)&.writes == true
  end

  def change_possible?(entry)
    return !connection_tool(entry).read_only? if connection?(entry)

    capability?(entry) && Chat::Tools::Target.capability_spec(entry.name)&.writes == true
  end

  def outcome(entry, text)
    waiting = @run.held? || (entry.tool.respond_to?(:waiting?) && entry.tool.waiting?) || text.to_s.start_with?(Chat::Tools::WAITING)
    return OUTCOME_WAITING if waiting

    @run.failed? ? OUTCOME_FAILED : OUTCOME_OK
  end

  # A connection's answer as the provider gave it, and anything else out of the frame the model reads it in.
  def answer_text(entry, text)
    result = connection?(entry) && !entry.tool.failed? && entry.tool.last_result
    return Array(result["content"]).filter_map { |part| part["text"] }.join("\n") if result

    FirefightAi::Evidence.unframe(text).body
  end

  def error(message) = { "error" => { "message" => message.to_s } }

  # The run the calls are made as, with no chat to save a large answer in, since a command reads it whole, and noting
  # whether the call failed or was held for an approval.
  class Caller < SimpleDelegator
    def chat = nil

    def progress_listener(_tool_call_id) = nil

    def reset!
      @failed = false
      @held = false
    end

    def failed? = @failed == true

    def held? = @held == true

    def call_failed!(kind)
      @failed = true
      __getobj__.call_failed!(kind) if __getobj__.respond_to?(:call_failed!)
    end

    def hold!(...)
      @held = true
      __getobj__.hold!(...)
    end
  end
end
