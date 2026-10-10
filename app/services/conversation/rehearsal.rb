# Replays a chat where nobody in the workspace sees it, to measure Halon. Halon runs on its real prompt and loop, on the
# model it is given, and every tool call is answered from the case's record, so only its reasoning differs between two
# replays. The person's turns are said in order, and a confirmation is answered the way the case says the person did.
# Nothing is posted and nothing outside Firefight is reached.
class Conversation::Rehearsal
  Replay = Data.define(:chat, :transcript, :turns_used)

  # The system message ends with what the runner added for this chat, which always starts by saying who is asking.
  CONTEXT = /^You are acting for .*/m

  # A replay that reaches this many rounds in one turn without the person answering has a loop, not a conversation.
  MAX_ROUNDS = 12

  def self.replay!(bench_case, result:, model:)
    new(bench_case, result, model).run
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
                                            result: call.result.content.to_s, failed: call.failed, times: 1, reads: false, after: nil)
      end,
      expect: Conversation::BenchCase::Expect.none
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
                                               reads: reads, reads_when: {}, confirms: live.requires_approval?, default: nil, base: base, group: nil)
    end

    keys = calls.flat_map { |call| Conversation::Rehearsal.asked(call.arguments).keys }.uniq
    Conversation::BenchCase::Tool.new(
      name: name, description: "No longer offered. Described from how its calls looked.",
      parameters: { "type" => "object", "properties" => keys.index_with { {} } }, source: Chat::Skill::SOURCE_FIREFIGHT,
      reads: reads, reads_when: {}, confirms: calls.any? { |call| call.approval.present? }, default: nil, base: false, group: nil
    )
  end
  private_class_method :captured_tool

  def initialize(bench_case, result, model)
    @case = bench_case
    @result = result
    @model = model
    @turns_used = 0
    @used = Hash.new(0)
    @ran = []
    @state = Conversation::Rehearsal::State.new(bench_case, @used, @ran)
    @opened = Set.new
  end

  def run
    chat = Chat.open!(owner: @result, workspace: @result.workspace, model_choice: @model)
    @case.turns.each do |turn|
      chat.add_message(role: Chat::Message::ROLE_USER, content: turn.said)
      # Saying something new moves past a confirmation still waiting, as it does live.
      chat.close_unfinished_calls!
      play(chat, turn.decisions.dup)
    end
    Replay.new(chat: chat.reload, transcript: Conversation::BenchTranscript.new(chat, @case), turns_used: @turns_used)
  end

  private

  # One turn, run again after each confirmation the person answers, as a live chat runs the next job once they decide.
  def play(chat, decisions)
    MAX_ROUNDS.times do
      outcome = respond(chat)
      return unless outcome.status == FirefightAi::AgentLoop::STATUS_WAITING

      pending = chat.to_llm.pending_approvals
      chat.request_decisions!(pending.map(&:id))
      return if decisions.empty?

      pending.each do |call|
        decision = decisions.shift or break
        chat.decide!(call.id, approved: decision == Conversation::BenchCase::DECISION_APPROVE)
      end
    end
  end

  def respond(chat)
    @looked_outside = false
    outcome = responder.run(
      chat: chat, tools: tools(chat), context: @case.context, budget: budget,
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

  # A chat starts with its own tools and open_tools, which makes the rest callable group by group, as it does live. A
  # case that offers no open_tools hands every tool over from the start.
  def tools(chat)
    return @case.tools.map { |definition| recorded(definition, chat) } unless @case.tool(Chat::Tools::Open.tool_name)

    in_hand = @case.tools.select { |definition| definition.base || @opened.include?(definition.name) }
    in_hand.reject { |definition| definition.name == Chat::Tools::Open.tool_name }.map { |definition| recorded(definition, chat) } +
      [ Conversation::Rehearsal::OpenTools.new(groups: groups, open: ->(names) { open(chat, names) }) ]
  end

  def recorded(definition, chat)
    Conversation::Rehearsal::RecordedTool.new(definition, bench_case: @case, chat: chat, used: @used, ran: @ran, state: @state)
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
    FirefightAi::AgentLoop::Budget.new(max_spend_cents: limits.max_spend_cents, max_turns: limits.max_turns)
  end
end
