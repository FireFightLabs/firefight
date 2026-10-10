module FirefightAi
  # Drives one run over a saved chat. The chat is the app's record, so the messages it adds are saved.
  class AgentLoop
    STATUS_ANSWERED = :answered
    STATUS_OUT_OF_BUDGET = :out_of_budget
    STATUS_OUT_OF_TURNS = :out_of_turns
    STATUS_STALLED = :stalled
    STATUS_REPEATED_TOOL_CALL = :repeated_tool_call
    STATUS_CANCELED = :canceled
    # The next run resumes from the saved chat once the person decides.
    STATUS_WAITING = :waiting

    STEP_RUNNING = :running
    STEP_DONE = :done

    REMINDER = "That reply did nothing. Call a tool to keep going, or conclude with what you have.".freeze
    LAST_TURN = "This run has spent its budget. Conclude now with the evidence you already have.".freeze

    MICROS_PER_CENT = 10_000

    # Micros, the ledger's unit, never rounded. The cap is still set in cents.
    Budget = Data.define(:max_spend_cents, :max_turns, :turns_used, :spent_micros) do
      def initialize(max_spend_cents:, max_turns:, turns_used: 0, spent_micros: 0) = super
    end

    Turn = Data.define(:turns_used, :spent_micros)
    Step = Data.define(:key, :tool, :status, :arguments) do
      def initialize(key:, tool:, status:, arguments: {}) = super
    end
    Outcome = Data.define(:status, :turns_used, :spent_micros)

    # reply_is_answer is what separates a conversation from an investigation. In a chat the person
    # is waiting for a reply, in a run only a conclusion ends it.
    # nudge is how the app saves the loop's own words, so it can tell them from what a person said.
    # memory is the saved chat when it can make room for itself, which lets a long run outlive its window.
    # check is what to ask before an answer goes out, or nil when none is owed yet. An answer it is owed is held back
    # unseen, hold is how the app keeps that draft out of what the person reads, and the answer after the check goes out.
    # take_messages adds what a person sent while the agent worked to the chat and says whether there was any. It is
    # called only between a tool's result and the next model call, the one place a new message keeps the chat valid.
    # output is the FirefightAi::OutputCap a turn may write, nil to leave the provider's own.
    # choice is the ModelChoice the chat runs on and purpose what it is for. When the workspace's own account runs dry or
    # refuses its key, the next account in its order takes the run over at the same step.
    # purse is what the run has spent (Purse), shared with helpers a tool starts beside the loop, so what they spend counts
    # against this budget too. A fresh one starts from the budget's spend.
    def initialize(chat:, budget:, answered:, inference:, canceled: -> { false }, on_step: nil, on_chunk: nil,
                   reply_is_answer: false, nudge: nil, memory: nil, check: nil, hold: nil, take_messages: nil, output: nil,
                   choice: nil, purpose: AiPurpose::INVESTIGATION, purse: nil)
      @chat = chat
      @choice = choice || ModelChoice.new(model: inference[:model], provider: inference[:provider])
      @purpose = purpose
      @output = output
      @output_limit = output&.max
      @room = Room.new(chat, memory)
      @nudge = nudge || ->(text) { chat.add_message(role: :user, content: text) }
      @on_chunk = on_chunk
      @budget = budget
      @answered = answered
      @canceled = canceled
      @inference = inference.merge(@choice.ledger)
      @turns = budget.turns_used
      @purse = purse || Purse.new(budget.spent_micros)
      @reported_micros = @purse.spent
      @reminders = 0
      @reply_is_answer = reply_is_answer
      @check = check
      @hold = hold
      @take_messages = take_messages
      @seen_tool_call_ids = messages.flat_map { |message| message.tool_calls&.keys || [] }.to_set
      report_steps_to(on_step) if on_step
    end

    # The caller hears about a tool as the agent reaches for it, and again when it answers.
    def report_steps_to(on_step)
      llm = @chat.to_llm
      llm.before_tool_call do |tool_call|
        on_step.call(
          Step.new(key: tool_call.id, tool: tool_call.name, status: STEP_RUNNING, arguments: tool_call.arguments)
        )
      end
      # after_tool_result only gets the tool's return value, which cannot name its call, so the saved result message is used.
      llm.after_message do |message|
        next unless message.tool_result?

        on_step.call(Step.new(key: message.tool_call_id, tool: nil, status: STEP_DONE))
      end
    end

    def run(&on_turn)
      FirefightAi.ensure_paid!(@choice)
      @on_turn = on_turn
      @chat.to_llm.with_max_output_tokens(@output_limit) if @output_limit
      loop do
        stop = stop_reason
        return outcome(stop) if stop
        return outcome(STATUS_WAITING) if @chat.to_llm.awaiting_approval?

        message = advance
        return outcome(STATUS_STALLED) if message.nil?
        unless message.role == :assistant
          report_spent_beside
          next
        end

        record_turn(message)

        repeated = repeated_tool_call_ids(message)
        return outcome(STATUS_REPEATED_TOOL_CALL) if repeated.any?

        stop = handle_plain_reply(message)
        return outcome(stop) if stop
      end
    end

    private

    def stop_reason
      return STATUS_ANSWERED if @answered.call
      return STATUS_CANCELED if @canceled.call
      # Running tools already asked for costs nothing, and a provider refuses a chat with anything between a call and its
      # result, including the next question in a chat that stopped before the result was saved.
      return nil if tools_pending?
      return STATUS_OUT_OF_TURNS if @turns >= @budget.max_turns
      return nil if @purse.spent < @budget.max_spend_cents * MICROS_PER_CENT
      return STATUS_OUT_OF_BUDGET if @last_turn_offered

      # One last turn, which may go over the cap.
      @last_turn_offered = true
      @nudge.call(LAST_TURN)
      nil
    end

    # Only a model call is billed. Running the tools the model already asked for is not.
    def advance
      return @chat.step if tools_pending?

      # Someone said something new, so a reply that did nothing before this is not held against the agent.
      @reminders = 0 if @take_messages&.call
      @room.make { handover_note }
      generate
    end

    # A provider that still says too long gets the chat rebuilt and one more try, never a second. A refusal for credit
    # goes to the next account when one can carry on, and otherwise fails the run.
    def generate
      Inference.track(tracked) { @chat.step(&streamer) }.first
    rescue RubyLLM::ContextLengthExceededError
      raise if @made_room_after_refusal || !@room.possible?

      @made_room_after_refusal = true
      @room.make_after_refusal
      retry
    rescue RubyLLM::Error => e
      raise unless take_over(e)

      retry
    end

    # The next account carries on from the same step, on its own model and with its own cap. False when none can.
    def take_over(error)
      following = FirefightAi.take_over(@choice, error, purpose: @purpose, workspace: @inference[:workspace])
      return false unless following

      @choice = following
      FirefightAi.bind(@chat, following)
      @inference = @inference.merge(following.ledger)
      if @output
        @output = FirefightAi.output_cap(@purpose, choice: following)
        @output_limit = @output.max
        @chat.to_llm.with_max_output_tokens(@output_limit)
      end
      true
    end

    def tracked = @output_limit ? @inference.merge(max_output_tokens: @output_limit) : @inference

    # Written with everything still in view, which is what makes it worth more than a summary written
    # afterwards. No tools, since this turn is only for the note.
    def handover_note
      llm = @chat.to_llm
      llm.with_tool_options(choice: :none)
      @nudge.call(Room::HANDOVER)
      note = Inference.track(tracked) { @chat.step }.first
      record_turn(note) if note
      note&.content.to_s
    ensure
      llm&.with_tool_options(choice: nil)
    end

    # Streaming still reports usage, so a streamed turn is billed like any other. A reply that may be held is not streamed.
    def streamer
      return nil if @on_chunk.nil? || check_owed

      lambda do |chunk|
        text = chunk.content
        @on_chunk.call(text) if text.is_a?(String) && !text.empty?
      end
    end

    def tools_pending?
      response = messages.reverse.find { |message| message.role != :system && !message.tool_result? }
      return false unless response&.tool_call?

      answered = messages.filter_map { |message| message.tool_call_id if message.tool_result? }
      (response.tool_calls.keys - answered).any?
    end

    def record_turn(message)
      @turns += 1
      @purse.add((message.cost&.total.to_f * 1_000_000).round)
      @room.saw(message)
      report_turn
    end

    # A tool that ran helpers spent from the purse without a turn of the loop's own, so the caller hears it at once.
    def report_spent_beside
      report_turn if @purse.spent != @reported_micros
    end

    def report_turn
      @reported_micros = @purse.spent
      @on_turn&.call(Turn.new(turns_used: @turns, spent_micros: @reported_micros))
    end

    # RubyLLM skips a call whose id already has a result, so a repeat pays for turns that run nothing.
    def repeated_tool_call_ids(message)
      ids = message.tool_calls&.keys || []
      repeated = ids & @seen_tool_call_ids.to_a
      @seen_tool_call_ids.merge(ids)
      repeated
    end

    def handle_plain_reply(message)
      if message.tool_call?
        @reminders = 0
        return nil
      end

      if @reply_is_answer
        return nil if asked_for_check?

        return STATUS_ANSWERED
      end

      return STATUS_STALLED if @reminders.positive?

      @reminders += 1
      @nudge.call(REMINDER)
      nil
    end

    # The draft stays in the chat, so the check can argue with it, and the reply after it is the answer.
    def asked_for_check?
      text = check_owed
      return false unless text

      @checked = true
      @hold&.call
      @nudge.call(text)
      true
    end

    # Once per question, and never on the last turn a budget buys, which has no room for another.
    def check_owed
      return nil if @check.nil? || @checked || @last_turn_offered

      @check.call.presence
    end

    # The record's messages are rows. These are the ones the model sees.
    def messages = @chat.to_llm.messages

    def outcome(status) = Outcome.new(status: status, turns_used: @turns, spent_micros: @purse.spent)
  end
end
