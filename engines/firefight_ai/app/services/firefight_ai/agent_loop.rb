module FirefightAi
  # Drives one run of the agent over a saved chat. The chat is the app's record, so every message
  # it adds is saved. The caller supplies the budget and a way to ask whether the agent has answered.
  class AgentLoop
    STATUS_ANSWERED = :answered
    STATUS_OUT_OF_BUDGET = :out_of_budget
    STATUS_OUT_OF_TURNS = :out_of_turns
    STATUS_STALLED = :stalled
    STATUS_REPEATED_TOOL_CALL = :repeated_tool_call

    REMINDER = "That reply did nothing. Call a tool to keep going, or conclude with what you have.".freeze
    LAST_TURN = "This run has spent its budget. Conclude now with the evidence you already have.".freeze

    MICROS_PER_CENT = 10_000

    Budget = Data.define(:max_spend_cents, :max_turns, :turns_used, :spent_cents) do
      def initialize(max_spend_cents:, max_turns:, turns_used: 0, spent_cents: 0) = super
    end

    Turn = Data.define(:turns_used, :spent_cents)
    Outcome = Data.define(:status, :turns_used, :spent_cents)

    def initialize(chat:, budget:, answered:, inference:)
      @chat = chat
      @budget = budget
      @answered = answered
      @inference = inference
      @turns = budget.turns_used
      @spend_micros = budget.spent_cents * MICROS_PER_CENT
      @reminders = 0
      @seen_tool_call_ids = messages.flat_map { |message| message.tool_calls&.keys || [] }.to_set
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
      return STATUS_OUT_OF_TURNS if @turns >= @budget.max_turns
      return nil if spent_cents < @budget.max_spend_cents
      return STATUS_OUT_OF_BUDGET if @last_turn_offered

      # One last turn to answer with what it has, which may go slightly over the cap.
      @last_turn_offered = true
      @chat.add_message(role: :user, content: LAST_TURN)
      nil
    end

    # Only a model call is billed. Running the tools the model already asked for is not.
    def advance
      return @chat.step if tools_pending?

      Inference.track(@inference) { @chat.step }.first
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
      yield Turn.new(turns_used: @turns, spent_cents: spent_cents) if block_given?
    end

    # RubyLLM skips a tool call whose id already has a result, so a model that repeats an id
    # would never see the tool run and would keep paying for another turn.
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

      return STATUS_STALLED if @reminders.positive?

      @reminders += 1
      @chat.add_message(role: :user, content: REMINDER)
      nil
    end

    # The record's own messages are Active Record rows, the model's are the ones RubyLLM holds.
    def messages = @chat.to_llm.messages

    def spent_cents = (@spend_micros.to_f / MICROS_PER_CENT).ceil

    def outcome(status) = Outcome.new(status: status, turns_used: @turns, spent_cents: spent_cents)
  end
end
