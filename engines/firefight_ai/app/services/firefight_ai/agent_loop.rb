module FirefightAi
  # Drives one run over a saved chat. The chat is the app's record, so the messages it adds are saved.
  class AgentLoop
    STATUS_ANSWERED = :answered
    STATUS_OUT_OF_BUDGET = :out_of_budget
    STATUS_OUT_OF_TURNS = :out_of_turns
    STATUS_STALLED = :stalled
    STATUS_REPEATED_TOOL_CALL = :repeated_tool_call
    STATUS_CANCELED = :canceled

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
    def initialize(chat:, budget:, answered:, inference:, canceled: -> { false }, on_step: nil, on_chunk: nil,
                   reply_is_answer: false)
      @chat = chat
      @on_chunk = on_chunk
      @budget = budget
      @answered = answered
      @canceled = canceled
      @inference = inference
      @turns = budget.turns_used
      @spend_micros = budget.spent_micros
      @reminders = 0
      @reply_is_answer = reply_is_answer
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
      loop do
        stop = stop_reason
        return outcome(stop) if stop

        message = advance
        return outcome(STATUS_STALLED) if message.nil?
        next unless message.role == :assistant

        record_turn(message, &on_turn)

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
      return STATUS_OUT_OF_TURNS if @turns >= @budget.max_turns
      return nil if @spend_micros < @budget.max_spend_cents * MICROS_PER_CENT
      return STATUS_OUT_OF_BUDGET if @last_turn_offered

      # One last turn, which may go over the cap.
      @last_turn_offered = true
      @chat.add_message(role: :user, content: LAST_TURN)
      nil
    end

    # Only a model call is billed. Running the tools the model already asked for is not.
    def advance
      return @chat.step if tools_pending?

      Inference.track(@inference) { @chat.step(&streamer) }.first
    end

    # Streaming still reports usage, so a streamed turn is billed like any other.
    def streamer
      return nil unless @on_chunk

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
      @spend_micros += (message.cost&.total.to_f * 1_000_000).round
      yield Turn.new(turns_used: @turns, spent_micros: @spend_micros) if block_given?
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

      return STATUS_ANSWERED if @reply_is_answer

      return STATUS_STALLED if @reminders.positive?

      @reminders += 1
      @chat.add_message(role: :user, content: REMINDER)
      nil
    end

    # The record's messages are rows. These are the ones the model sees.
    def messages = @chat.to_llm.messages

    def outcome(status) = Outcome.new(status: status, turns_used: @turns, spent_micros: @spend_micros)
  end
end
