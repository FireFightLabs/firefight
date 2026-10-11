# A tool in a replayed chat. It is offered exactly as the case describes it and answers from the case's world, so
# nothing outside Firefight is reached and only Halon's reasoning differs between two replays. A call that changes
# something waits for the person as it would live, and a call that only reads never does. Firefight's own watch and plan
# tools answer from the replay's state instead (Conversation::Rehearsal::State), so they show what Halon changed.
class Conversation::Rehearsal::RecordedTool < RubyLLM::Tool
  # world and state are shared by every tool in the replay, the scenario's world as the replay moved it and the watches
  # and plans made in it. unscripted collects the ids of calls nothing in the case answered.
  def initialize(definition, bench_case:, chat:, world:, state:, unscripted:)
    super()
    @definition = definition
    @bench_case = bench_case
    @chat = chat
    @world = world
    @state = state
    @unscripted = unscripted
  end

  def name = @definition.name

  def description = @definition.description

  def parameters_schema
    schema = @definition.parameters.deep_stringify_keys
    @definition.confirms ? Chat::Tools.with_intent(schema) : schema
  end

  def requires_approval? = @definition.confirms

  # A call that reads runs at once. One that changes something runs once the person approves it, which the replay
  # records on the call as a live chat does.
  def approval_resolver
    lambda do |tool_call|
      next true unless @definition.asks?(Conversation::Rehearsal.asked(tool_call.arguments))

      { Chat::APPROVAL_APPROVED => true, Chat::APPROVAL_DENIED => false }[@chat.tool_calls.where(tool_call_id: tool_call.id).pick(:approval)]
    end
  end

  def call(tool_call: nil, **arguments)
    asked = Conversation::Rehearsal.asked(arguments)
    return @state.call(name, asked) if @state.handles?(name)

    found = @world.answer!(name, asked)
    return unscripted(tool_call, asked) unless found

    @chat.mark_failed!(tool_call.id) if found.failed && tool_call
    found.result
  end

  private

  # A read that finds nothing is an answer, not a failure. A change nothing answers, or a call a real chat never made, failed.
  def unscripted(tool_call, asked)
    said = @bench_case.unscripted(name, asked)
    if tool_call
      @unscripted << tool_call.id
      @chat.mark_failed!(tool_call.id) unless said == Conversation::BenchCase::NOTHING_FOUND
    end
    said
  end
end
