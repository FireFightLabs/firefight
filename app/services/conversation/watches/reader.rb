# One read a watch makes: a capability routed to the connection that holds the resource, run as the person who asked
# through the gateway, so their grants, the connection's setup and the ledger all apply exactly as in their chat. Only
# capabilities that read are ever asked. A read an approval rule covers is never made, since nobody is there to approve
# it each minute.
class Conversation::Watches::Reader
  # Why a read cannot be made, in words the person reads.
  class Refused < StandardError; end
  # The provider did not answer this time, which the next check tries again.
  class Unanswered < StandardError; end

  Answer = Data.define(:result, :call) do
    def text = Integrations::Capabilities::Answers.text(result)
    def failed? = result["isError"] == true
  end

  def initialize(workspace:, principal:, conversation:)
    @workspace = workspace
    @principal = principal
    @conversation = conversation
  end

  # The routed call alone, raising Refused with words when there is none the person may make.
  def route(key, given)
    spec = Integrations::Capabilities.spec(key)
    raise Refused, "#{spec.tool_name} changes things, and a watch only reads." if spec.writes

    callable = Integrations::Capabilities.callable(@workspace, key, @principal)
    call = Integrations::Capabilities.resolve(@workspace, key, given, callable, principal: @principal)
    raise Refused, held_words(call) if held?(call)

    call
  rescue Integrations::Capabilities::Unroutable => error
    raise Refused, refusal_for(key, given, error.message)
  end

  def read(key, given) = read_call(route(key, given))

  def read_call(call)
    answer = Answer.new(result: run(call), call: call)
    return answer if call.fallback.nil? || Integrations::Capabilities.definitive?(answer.result)

    Answer.new(result: run(call.fallback), call: call.fallback)
  end

  # What one of Halon's read tools answered, by the name Halon calls it, as the person who asked. Text, and whether the
  # call failed.
  Said = Data.define(:text, :failed) do
    def failed? = failed
  end

  def read_tool(agent, name, arguments)
    entry = agent.tools[name.to_s]
    raise Refused, "#{name} is not a read tool #{who} may use, so a watch cannot read with it." unless entry

    agent.started_call!
    text = entry.tool.call(**arguments.to_h.transform_keys(&:to_sym))
    Said.new(text: FirefightAi::Evidence.unframe(text).body, failed: agent.failed?)
  end

  # A job's or step's log, read with the provider tool the run named on the connection that answered for the run. Only a
  # tool that reads, and only when nothing holds it for approval.
  def read_log(environment_row, log)
    handle = log[Integrations::Capabilities::History::LOG_TOOL].to_s
    tool = environment_row.integration.tools.enabled.available.find_by(name: handle)
    raise Refused, "#{handle} is not switched on, so the log could not be read." unless tool

    arguments = log[Integrations::Capabilities::History::LOG_ARGUMENTS].to_h
    raise Refused, "#{handle} changes things, so a watch does not read a log with it." unless tool.reads_call?(arguments)

    scope = environment_row.ability_scope
    raise Refused, held_tool_words(tool) if Chat::ToolCall.held_by_rule?(workspace: @workspace, action_key: tool.action_key, scope: scope, params: arguments)

    result = authorized(tool, scope, arguments) do
      tool.integration.executor.call(tool: tool, environment_row: environment_row, arguments: arguments, box_key: @conversation.code_box_key)
    end
    Answer.new(result: result, call: nil)
  end

  private

  def run(call)
    authorized(call.tool, call.scope, call.arguments) do
      answer = call.tool.integration.executor.call(tool: call.tool, environment_row: call.environment_row, arguments: call.arguments,
                                                   box_key: @conversation.code_box_key)
      call.present_result(answer)
    end
  end

  def authorized(tool, scope, arguments)
    Chat::ToolCall.run!(
      workspace: @workspace, principal: @principal, action_key: tool.action_key, scope: scope, params: arguments,
      context: { source: Chat::Watch::SOURCE, incident_id: @conversation.incident_id }.compact
    ) do |authorization|
      presented = yield
      Mcp::ToolDispatcher.ledger_failure(authorization, presented)
      presented
    end
  rescue AbilityGateway::Denied
    raise Refused, "#{who} may no longer use #{tool.integration.name}'s #{tool.name}."
  rescue AbilityGateway::PendingApproval
    raise Refused, held_tool_words(tool)
  rescue Integrations::Error => error
    raise Unanswered, "#{tool.integration.name} did not answer: #{error.message.truncate(200)}"
  end

  def held?(call) = Chat::ToolCall.held_by_rule?(workspace: @workspace, action_key: call.tool.action_key, scope: call.scope, params: call.arguments)

  def held_words(call) = held_tool_words(call.tool)

  def held_tool_words(tool) = "An approval rule covers #{tool.integration.name}'s #{tool.name}, and nobody is there to approve each read."

  # A resource whose provider keeps no run history says why, in the provider's own note.
  def refusal_for(key, given, said)
    return said unless key == Integrations::Capabilities::HISTORY

    notes = Integrations::Capabilities.history_notes(@workspace, given[Integrations::Capabilities::RESOURCE_ARG], principal: @principal)
    notes.presence ? "#{said} #{notes.join(' ')}" : said
  end

  def who = @principal.try(:display_name) || "The person who asked"
end
