# Replays a chat where nobody in the workspace sees it, to measure Halon. Halon runs on its real prompt and loop, on the
# model it is given, and every tool call is answered from the case's world, so only its reasoning differs between two
# replays. The person's turns are said in order, a confirmation is answered the way the case says the person did, and a
# question asked in plain words is answered from what the case says the person wants (Conversation::BenchCase::Person).
# Nothing is posted and nothing outside Firefight is reached.
class Conversation::Rehearsal
  Replay = Data.define(:chat, :transcript, :turns_used)

  # The system message ends with what the runner added for this chat, which always starts by saying who is asking.
  CONTEXT = /^You are acting for .*/m

  # A replay that reaches this many rounds in one turn without the person answering has a loop, not a conversation.
  MAX_ROUNDS = 12
  # How many questions in plain words the person answers in one turn before the next thing they say.
  FOLLOW_UPS = 2

  # Tools Halon's instructions name that a live chat holds whatever a scenario lists. The skills and what changed are
  # offered with no connection at all, and the rest come with any connected system. A scenario that leaves them out
  # still has them, as live, so an instruction never names a tool that is not there.
  ALWAYS_OFFERED = [ Chat::Tools::UseSkill.tool_name, ResourceMap::Timeline::TOOL_NAME ].freeze
  CONNECTED_OFFERED = [
    Integrations::Capabilities.spec(Integrations::Capabilities::STATUS).tool_name, Integrations::Capabilities::KEY_QUERY_TOOL,
    Integrations::Capabilities::LOG_PATTERNS_TOOL
  ].freeze

  # max_spend_cents caps what the replay may spend, below the workspace's own limit, such as what is left of a run's budget.
  def self.replay!(bench_case, result:, model:, max_spend_cents: nil)
    new(bench_case, result, model, max_spend_cents).run
  end

  # The case as a live chat would hold it, with its own tools and those a chat is offered whatever the scenario lists,
  # from the shared tools. A real chat replayed keeps exactly the tools it had.
  def self.as_offered(bench_case, shared: Conversation::BenchCase.shared_tools)
    return bench_case if bench_case.captured?

    wanted = ALWAYS_OFFERED + (bench_case.tools.any?(&:outside?) ? CONNECTED_OFFERED : [])
    added = (wanted - bench_case.tools.map(&:name)).map { |name| Conversation::BenchCase.tool_from(shared.fetch(name)) }
    bench_case.offering(added)
  end

  # What a call asked for, without the sentence a confirmation leads with, which the tool itself never sees.
  def self.asked(arguments) = arguments.to_h.stringify_keys.except(Chat::Tools::INTENT_ARG)

  # A real chat as a case: what the person said and decided, the tools its calls used as they are offered today (or
  # as the call looked, for a tool that is gone), and what each call answered. Nothing is said about its right outcome.
  def self.capture(conversation)
    chat = conversation.chat or raise Conversation::BenchCase::Invalid, "This conversation has no chat with Halon."
    turn = Conversation::Turn.new(conversation, asker: conversation.started_by)
    live = live_tools(turn)
    messages = chat.messages.includes(ruby_llm_tool_calls: :result).to_a
    calls = messages.flat_map(&:ruby_llm_tool_calls).sort_by(&:created_at)

    Conversation::BenchCase.new(
      key: "chat-#{conversation.id}", title: conversation.display_title, shape: "", source: "chat #{conversation.id}",
      context: messages.find { |message| message.role == Chat::Message::ROLE_SYSTEM }&.content.to_s[CONTEXT].to_s.strip,
      turns: captured_turns(messages),
      tools: calls.map(&:name).uniq.map { |name| captured_tool(name, live[name], calls.select { |call| call.name == name }, conversation.workspace) },
      answers: calls.select(&:result).map do |call|
        Conversation::BenchCase::Answer.new(tool: call.name, match: Conversation::Rehearsal.asked(call.arguments),
                                            result: call.result.content.to_s, failed: call.failed, times: 1)
      end,
      expect: Conversation::BenchCase::Expect.none, captured: true
    ).tap(&:check!)
  end

  # Each tool a chat could be offered today with whose it is, Firefight's own or a provider's, and whether a chat holds it
  # from the start or opens it.
  def self.live_tools(turn)
    own = Conversation::Tools.for(turn, offer: ->(_tools) { }).to_h { |tool| [ tool.name.to_s, [ tool, Chat::Skill::SOURCE_FIREFIGHT, true ] ] }
    own.merge(Chat::Tools.catalog(turn).select(&:tool).to_h { |entry| [ entry.name.to_s, [ entry.tool, entry.source, false ] ] })
  end
  private_class_method :live_tools

  # Each thing the person said starts a turn, and the confirmations they answered before saying the next belong to it.
  def self.captured_turns(messages)
    turns = []
    messages.each do |message|
      if message.role == Chat::Message::ROLE_USER && !message.nudge
        turns << { said: message.content.to_s, decisions: [] }
      elsif turns.any?
        message.ruby_llm_tool_calls.sort_by(&:created_at).each do |call|
          decision = { Chat::APPROVAL_APPROVED => Conversation::BenchCase::DECISION_APPROVE, Chat::APPROVAL_DENIED => Conversation::BenchCase::DECISION_DENY }[call.approval]
          turns.last[:decisions] << decision if decision
        end
      end
    end
    turns.reject { |turn| turn[:said].blank? }.map { |turn| Conversation::BenchCase::Turn.new(**turn) }
  end
  private_class_method :captured_turns

  # A tool still offered is described as it is now, so a changed description or rule is what the replay tests. One that
  # is gone is described from how its calls looked, and asks the person when any call to it did.
  def self.captured_tool(name, live, calls, workspace)
    reads = Chat::Tools.kind(name, workspace) == Chat::Tools::KIND_READ
    if live
      live, owner, base = live
      schema = live.parameters_schema.deep_stringify_keys
      schema["properties"] = schema["properties"].to_h.except(Chat::Tools::INTENT_ARG)
      schema["required"] = Array(schema["required"]) - [ Chat::Tools::INTENT_ARG ]
      return Conversation::BenchCase::Tool.new(name: name, description: live.description.to_s, parameters: schema, source: owner.to_s,
                                               reads: reads, reads_when: {}, confirms: live.requires_approval?, default: nil, base: base, group: nil,
                                               reads_like: nil, request: nil)
    end

    keys = calls.flat_map { |call| Conversation::Rehearsal.asked(call.arguments).keys }.uniq
    Conversation::BenchCase::Tool.new(
      name: name, description: "No longer offered. Described from how its calls looked.",
      parameters: { "type" => "object", "properties" => keys.index_with { {} } }, source: Chat::Skill::SOURCE_FIREFIGHT,
      reads: reads, reads_when: {}, confirms: calls.any? { |call| call.approval.present? }, default: nil, base: false, group: nil,
      reads_like: nil, request: nil
    )
  end
  private_class_method :captured_tool

  def initialize(bench_case, result, model, max_spend_cents)
    @case = Conversation::Rehearsal.as_offered(bench_case)
    @result = result
    @model = model
    @max_spend_cents = max_spend_cents
    @turns_used = 0
    @world = Conversation::BenchCase::World.new(@case)
    @state = Conversation::Rehearsal::State.new(@world)
    @unscripted = Set.new
    @opened = Set.new
  end

  def run
    chat = Chat.open!(owner: @result, workspace: @result.workspace, model_choice: @model)
    @case.turns.each do |turn|
      @world.advance!(turn.sets)
      say(chat, turn.said)
      play(chat, turn)
    end
    Replay.new(chat: chat.reload, transcript: Conversation::BenchTranscript.new(chat, @case, unscripted: @unscripted), turns_used: @turns_used)
  end

  private

  # Saying something new moves past a confirmation still waiting, as it does live.
  def say(chat, text)
    chat.add_message(role: Chat::Message::ROLE_USER, content: text)
    chat.close_unfinished_calls!
  end

  # One turn, run again after each confirmation the person answers, as a live chat runs the next job once they decide,
  # and after each question in plain words they answer.
  def play(chat, turn)
    decisions = turn.decisions.dup
    follow_ups = 0
    MAX_ROUNDS.times do
      outcome = respond(chat)
      if outcome.status == FirefightAi::AgentLoop::STATUS_WAITING
        return unless decide(chat, decisions)

        next
      end
      return unless outcome.status == FirefightAi::AgentLoop::STATUS_ANSWERED && follow_ups < FOLLOW_UPS

      reply = @case.person.answer(last_reply(chat), turn: turn, decisions: decisions) or return
      follow_ups += 1
      say(chat, reply)
    end
  end

  # Answers the confirmations waiting, in order, while the turn has decisions left. False when it has none, so the
  # confirmation waits and the turn ends on it.
  def decide(chat, decisions)
    pending = chat.to_llm.pending_approvals
    chat.request_decisions!(pending.map(&:id))
    return false if decisions.empty?

    pending.each do |call|
      decision = decisions.shift or break
      chat.decide!(call.id, approved: decision == Conversation::BenchCase::DECISION_APPROVE)
    end
    true
  end

  # What Halon said last since the person spoke, which is what a question in it would be put to them in.
  def last_reply(chat)
    spoken = chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false).maximum(:created_at)
    chat.messages.where(role: Chat::Message::ROLE_ASSISTANT, nudge: false).where(created_at: spoken..)
        .reorder(created_at: :desc, id: :desc).find { |message| message.content.present? }&.content
  end

  def respond(chat)
    @looked_outside = false
    outcome = responder.run(
      chat: chat, tools: tools(chat), deferred_tools: deferred(chat), context: @case.context, budget: budget,
      on_step: method(:note_step), nudge: chat.method(:nudge!), memory: chat,
      check: -> { FirefightAi::Responder::CHECK if @looked_outside }, hold: chat.method(:hold_last_reply!)
    )
    @turns_used += outcome.turns_used
    outcome
  end

  # A connected system is what a claim about a cause rests on, so reading one owes the answer a check, as it does live.
  def note_step(step)
    definition = step.tool && @case.tool(step.tool.to_s)
    @looked_outside ||= definition.present? && definition.outside? && definition.reads?(Conversation::Rehearsal.asked(step.arguments))
  end

  # A chat starts with its own tools and open_tools, which makes the rest callable group by group, as it does live. Where
  # the model's provider searches tools itself, Firefight's own tools are in hand from the start too and every connected
  # tool waits to be searched for (deferred), as Chat::Tools.presented hands them live. A case that offers no open_tools
  # hands every tool over from the start.
  def tools(chat)
    return @case.tools.map { |definition| recorded(definition, chat) } unless @case.tool(Chat::Tools::Open.tool_name)

    in_hand = @case.tools.select { |definition| in_hand?(definition) }
    in_hand.reject { |definition| definition.name == Chat::Tools::Open.tool_name }.map { |definition| recorded(definition, chat) } +
      [ Conversation::Rehearsal::OpenTools.new(groups: groups, open: ->(names) { open(chat, names) }, searched: searched?) ]
  end

  def deferred(chat)
    return [] unless searched? && @case.tool(Chat::Tools::Open.tool_name)

    @case.tools.reject { |definition| in_hand?(definition) || definition.name == Chat::Tools::Open.tool_name }.map { |definition| recorded(definition, chat) }
  end

  def in_hand?(definition) = definition.base || @opened.include?(definition.name) || (searched? && !definition.outside?)

  def searched?
    @searched = FirefightAi.tool_search?(responder.ai_model) unless defined?(@searched)
    @searched
  end

  # use_skill serves the real skills, and every other tool answers from the case.
  def recorded(definition, chat)
    if definition.name == Chat::Tools::UseSkill.tool_name && !@case.captured?
      return Conversation::Rehearsal::UseSkill.new(tools: @case.tools, open: ->(names) { open(chat, names) })
    end

    Conversation::Rehearsal::RecordedTool.new(definition, bench_case: @case, chat: chat, world: @world, state: @state, unscripted: @unscripted)
  end

  def groups
    @groups ||= @case.tools.reject { |definition| definition.base || definition.name == Chat::Tools::Open.tool_name }
                           .group_by(&:group_key)
  end

  # Makes the named tools callable for the rest of the chat, from the next model call on, and returns them.
  def open(chat, names)
    definitions = @case.tools.select { |definition| names.include?(definition.name) }
    @opened.merge(definitions.map(&:name))
    chat.with_tools(*definitions.map { |definition| recorded(definition, chat) })
    definitions
  end

  def responder
    @responder ||= FirefightAi::Responder.new(@result.workspace, inferable: @result, model: @model)
  end

  def budget
    limits = @result.workspace.conversation_limits
    cap = [ limits.max_spend_cents, @max_spend_cents ].compact.min
    FirefightAi::AgentLoop::Budget.new(max_spend_cents: cap, max_turns: limits.max_turns)
  end
end
