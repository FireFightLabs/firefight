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
    # Said before asking again for a reply that ran past the output limit in the middle of a tool call, since the same
    # reply written again would be cut off the same way.
    CUT_OFF = "Your last reply ran past the most you can write at once and was cut off in the middle of a tool call, so " \
              "nothing in it was run. Write it again shorter: fewer and tighter lines, or split it across calls.".freeze

    MICROS_PER_CENT = 10_000

    # A loop nobody can stop, whose tools run on its own thread.
    NEVER_CANCELED = -> { false }
    # How often a loop whose tools are running looks for a stop, in seconds.
    STOP_CHECK_EVERY = 1
    # How long a stopped loop lets a tool that had just answered finish saving its result, in seconds.
    SETTLE_AFTER_STOP = 1

    # Micros, the ledger's unit, never rounded. The cap is still set in cents.
    Budget = Data.define(:max_spend_cents, :max_turns, :turns_used, :spent_micros) do
      def initialize(max_spend_cents:, max_turns:, turns_used: 0, spent_micros: 0) = super
    end

    Turn = Data.define(:turns_used, :spent_micros)
    Step = Data.define(:key, :tool, :status, :arguments) do
      def initialize(key:, tool:, status:, arguments: {}) = super
    end
    Outcome = Data.define(:status, :turns_used, :spent_micros)
    # What a long running tool said about how far it got while it worked, by its call's key. value and total are counts
    # in the tool's own unit when it can count the work, nil when it says only message.
    Progress = Data.define(:key, :message, :value, :total)

    # reply_is_answer is what separates a conversation from an investigation. In a chat the person
    # is waiting for a reply, in a run only a conclusion ends it.
    # nudge is how the app saves the loop's own words, so it can tell them from what a person said.
    # memory is the saved chat when it can make room for itself, which lets a long run outlive its window.
    # take_messages adds what a person sent while the agent worked to the chat and says whether there was any. It is
    # called only between a tool's result and the next model call, the one place a new message keeps the chat valid.
    # output is the FirefightAi::OutputCap a turn may write, nil to leave the provider's own.
    # choice is the ModelChoice the chat runs on and purpose what it is for. When the workspace's own account runs dry or
    # refuses its key, the next account in its order takes the run over at the same step.
    # purse is what the run has spent (Purse), shared with helpers a tool starts beside the loop, so what they spend counts
    # against this budget too. A fresh one starts from the budget's spend.
    # on_backup is called with the choice that stopped answering, the backup taking over and the error, once per switch. Without it
    # a provider that stops answering fails the run as before, which a rehearsal needs to measure one model.
    # on_take_over is called the same way when the next account takes over from one that ran dry or refused its key. Without
    # it the handover is quiet, as it is unless a person picked the model.
    # on_progress hears a Progress each time a running tool reports how far it got (RubyLLM::Tool#progress), on the thread
    # the tool reports from, before the tool answers.
    # steady sends Halon's own loop at the deployment's loop temperature (FirefightAi.loop_temperature), again for each
    # model that takes over, so a chat and a run vary as little as the model allows.
    # checks look at a reply that would end the turn, each a callable given the reply that answers words to send it back
    # with, or nil to let it end. Each sends a turn back at most once, so a model that keeps answering the same way still
    # ends. A chat's checks are the line saying its next step (NextStep), its theory board and the challenger.
    # context is what the app says of how things stand now, which can change between turns. It is the last message of every
    # model call and is never saved, so the instructions and the history in front of it reach the provider as it cached
    # them, and the model reads the latest of it on each call.
    # retry_malformed asks the same model once more, once per run, when its reply held a tool call whose arguments could not
    # be read (RubyLLM::ToolCallParseError), which a chat, a helper and a specialist do so one bad reply does not end them.
    # canceled says whether someone stopped the run. It is read between steps and, while tools run, every
    # STOP_CHECK_EVERY seconds, so a stop ends the run whatever a tool is waiting on (run_tools).
    # hold_history is for a chat a person comes back to after a pause. A run's first call caches the history it starts
    # from, and memory keeps that boundary in the saved chat in place of the run before's (hold_history!), so the next
    # turn reads it whatever happened in between. Where the provider keeps a boundary for CACHE_BETWEEN_TURNS, the
    # instructions and that boundary last that long, and every other boundary keeps the provider's five minutes, which
    # costs less to write (cache_marks).
    def initialize(chat:, budget:, answered:, inference:, canceled: NEVER_CANCELED, on_step: nil, on_chunk: nil,
                   reply_is_answer: false, nudge: nil, memory: nil, take_messages: nil, output: nil,
                   choice: nil, purpose: AiPurpose::INVESTIGATION, purse: nil, on_backup: nil, on_take_over: nil, on_progress: nil,
                   steady: false, checks: [], retry_malformed: false, context: nil, hold_history: false)
      @chat = chat
      @choice = choice || ModelChoice.new(model: inference[:model], provider: inference[:provider])
      @purpose = purpose
      @memory = memory
      @holds_history = hold_history && !memory.nil?
      @hold_history = @holds_history
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
      @take_messages = take_messages
      @on_backup = on_backup
      @on_take_over = on_take_over
      @given_up_on = []
      @steady = steady
      @checks = checks.dup
      @retry_malformed = retry_malformed
      @context = context.presence
      steady!
      @seen_tool_call_ids = messages.flat_map { |message| message.tool_calls&.keys || [] }.to_set
      report_steps_to(on_step) if on_step
      report_progress_to(on_progress) if on_progress
    end

    def report_progress_to(on_progress)
      @chat.to_llm.after_tool_progress do |tool_call, progress|
        on_progress.call(Progress.new(key: tool_call.id, message: progress.message&.to_s, value: progress.value, total: progress.total))
      end
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
        return outcome(STATUS_CANCELED) if message.equal?(STOPPED)
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

    # What run_tools answers when a stop ended the tools.
    STOPPED = Object.new.freeze

    # Only a model call is billed. Running the tools the model already asked for is not.
    def advance
      return run_tools if tools_pending?

      # Someone said something new, so a reply that did nothing before this is not held against the agent.
      @reminders = 0 if @take_messages&.call
      @room.make { handover_note }
      generate
    end

    # The tools run on a thread of their own while the loop looks for a stop, so a stop ends the run at once, whether a
    # tool waits on a sandbox, a provider's API or a remote server. The tools are told through StopSignal, so a wait that
    # checks it gives up and tidies after itself, and the chat is cancelled, so RubyLLM saves no result for a tool that
    # answers after the stop. The loop lends its database connection to the tools while it waits.
    def run_tools
      return @chat.step if @canceled.equal?(NEVER_CANCELED)

      signal = Concurrent::Event.new
      tools = StopSignal.watching(signal) { Thread.new { beside_the_loop { @chat.step } } }
      tools.report_on_exception = false
      until wait_for(tools, STOP_CHECK_EVERY)
        next unless @canceled.call

        signal.set
        @chat.to_llm.cancel
        settle(tools)
        return STOPPED
      end
      tools.value
    end

    # Its own unit of work, so its connection goes back to the pool when it ends. Its errors reach the loop through
    # Thread#value, which reports them as it always did, so nothing reports them here.
    def beside_the_loop
      execution = Rails.application.executor.run!
      yield
    ensure
      execution&.complete!
    end

    # Joining raises what the tools raised, as running them on the loop's own thread would.
    def wait_for(thread, seconds)
      lend_connection
      ActiveSupport::Dependencies.interlock.permit_concurrent_loads { thread.join(seconds) }
    end

    # A tool that gives up on the stop raises, which nobody waits for any more.
    def settle(thread)
      wait_for(thread, SETTLE_AFTER_STOP)
    rescue StandardError
      nil
    end

    def lend_connection
      ActiveRecord::Base.connection_handler.connection_pool_list(:all).each do |pool|
        pool.release_connection unless pool.active_connection&.transaction_open?
      end
    end

    # A provider that still says too long gets the chat rebuilt and one more try, never a second. A reply that could not
    # be read is asked for again when the caller wants it (retry_malformed). A refusal for credit goes to the next account
    # when one can carry on, and otherwise fails the run. A provider that stopped answering, after RubyLLM's own retries,
    # hands the run to a backup when one is set up.
    def generate
      holding = @hold_history
      reply = Inference.track(tracked) { with_context_last(holding: holding) { @chat.step(&streamer) } }.first
      hold_history if holding
      reply
    rescue RubyLLM::ContextLengthExceededError
      raise if @made_room_after_refusal || !@room.possible?

      @made_room_after_refusal = true
      @room.make_after_refusal
      retry
    rescue RubyLLM::Error, *FirefightAi::PROVIDER_DOWN_ERRORS => e
      retry if ask_again?(e)
      raise unless take_over(e) || back_up(e) || fall_back(e)

      retry
    end

    # RubyLLM already took the unreadable reply out of the chat, so the same model is asked the same thing again, told
    # to write less when the reply was cut off at the output limit.
    def ask_again?(error)
      return false unless @retry_malformed && error.is_a?(RubyLLM::ToolCallParseError) && !@asked_again

      @nudge.call(CUT_OFF) if error.finish_reason == :max_tokens
      @asked_again = true
    end

    # The next account carries on from the same step, on its own model and with its own cap. False when none can.
    def take_over(error)
      following = FirefightAi.take_over(@choice, error, purpose: @purpose, workspace: @inference[:workspace])
      return false unless following

      failing = @choice
      switch_to(following)
      @on_take_over&.call(failing, following, error)
      true
    end

    # The backup carries on from the same step, and the app is told once for each switch so it can say so.
    def back_up(error)
      return false unless @on_backup && FirefightAi.backup_helps?(error)

      backup = FirefightAi.backup_for(@choice, purpose: @purpose, workspace: @inference[:workspace], tried: @given_up_on)
      return false unless backup

      failing = @choice
      @given_up_on << failing
      switch_to(backup)
      @on_backup.call(failing, backup, error)
      true
    end

    # A helper on quick work whose model is not there for the account carries on with the provider's next quick model.
    def fall_back(error)
      following = FirefightAi.quick_fallback(@choice, error, purpose: @purpose, tried: @given_up_on)
      return false unless following

      @given_up_on << @choice
      switch_to(following)
      true
    end

    def switch_to(following)
      @choice = following
      FirefightAi.bind(@chat, following)
      FirefightAi.present_tools(@chat, following)
      @inference = @inference.merge(following.ledger)
      steady!
      return unless @output

      @output = FirefightAi.output_cap(@purpose, choice: following)
      @output_limit = @output.max
      @chat.to_llm.with_max_output_tokens(@output_limit)
    end

    def steady!
      @chat.to_llm.with_temperature(FirefightAi.loop_temperature(@choice)) if @steady
    end

    def tracked = @output_limit ? @inference.merge(max_output_tokens: @output_limit) : @inference

    # Written with everything still in view, which is what makes it worth more than a summary written
    # afterwards. No tools, since this turn is only for the note.
    def handover_note
      llm = @chat.to_llm
      llm.with_tool_options(choice: :none)
      @nudge.call(Room::HANDOVER)
      note = Inference.track(tracked) { with_context_last { @chat.step } }.first
      record_turn(note) if note
      note&.content.to_s
    ensure
      llm&.with_tool_options(choice: nil)
    end

    # The context goes after everything the chat holds for this one call, and comes out again once the reply is in, so
    # the reply and the tool results after it are saved where they would be without it. Where the chat is cached as it
    # grows, the history in front of the context ends in a cache boundary for this call only, marked on a copy, so no
    # later call carries the mark. Otherwise a provider that caches at boundaries, such as Anthropic, would write the history with this context at
    # its end and find none of it on the next call, whose context comes after more of the chat. holding marks the
    # boundary the run's first call holds (hold_history).
    def with_context_last(holding: false)
      return yield unless @context

      llm = @chat.to_llm
      marks = cache_marks(llm, holding)
      marks.each { |message, copy| swap(llm.messages, message, copy) }
      note = llm.add_message(role: :user, content: @context)
      yield
    ensure
      if @context
        messages = @chat.to_llm.messages
        messages.delete_if { |message| message.equal?(note) } if note
        marks&.each { |message, copy| swap(messages, copy, message) }
      end
    end

    # Each message marked for this call with the copy that carries the mark. In a chat that holds its history, on a model
    # whose provider keeps a boundary for an hour, the saved boundaries (the instructions and the held history) and the
    # one a run's first call holds last that long, ahead of every five minute one as Anthropic requires. The lifetime is
    # decided on each call, so a chat a backup moved to another provider sends only what that provider takes.
    def cache_marks(llm, holding)
      return [] unless llm.caching

      lasting = FirefightAi::CACHE_BETWEEN_TURNS if @holds_history && FirefightAi.lasting_cache?(@choice)
      boundary = boundary_in(llm)
      @holding = boundary if holding
      saved = lasting ? llm.messages.select(&:cache_until_here?) : []
      [ *saved.map { |message| [ message, marked(message, lasting) ] }, *([ [ boundary, marked(boundary, (lasting if holding)) ] ] if boundary) ]
    end

    def marked(message, ttl) = message.dup.tap { |copy| copy.cache_until_here(ttl: ttl) }

    # The message the cached history ends at: the last one, or the one before a run of user messages, since OpenRouter
    # sends a run of plain messages as one text and a marked message as a block of its own. Marking the last of such a
    # run sent it differently on this call than on every call after, and each of those found nothing cached past the
    # run's start. Seen on a long chat, a call seconds after its history was cached read only the instructions and wrote
    # 270,000 tokens again. nil when that message cannot be marked.
    def boundary_in(llm)
      messages = llm.messages
      first = messages.size - 1
      first -= 1 while first.positive? && messages[first].role == :user && messages[first - 1].role == :user
      boundary = first == messages.size - 1 ? messages[first] : messages[first - 1]
      boundary if boundary && markable?(llm, boundary)
    end

    # The chat's first message after the instructions is never marked, since OpenRouter keys a route on it as sent, nor
    # is a reply with no words, which a provider refuses a boundary on.
    def markable?(llm, message)
      message.role != :system && !message.cache_until_here? && !opening?(llm, message) &&
        !(message.role == :assistant && message.content.to_s.strip.empty?)
    end

    # The boundary the run's first call was cached up to is kept in the saved chat, found by how many messages follow
    # it, in place of the one the run before kept. Only the first call of a run holds one.
    def hold_history
      @hold_history = false
      boundary = @holding
      @holding = nil
      index = boundary && messages.index { |message| message.equal?(boundary) }
      @memory.hold_history!(after: messages.size - 1 - index) if index
    end

    def opening?(llm, message) = llm.messages.find { |candidate| candidate.role != :system }.equal?(message)

    def swap(messages, from, to)
      index = messages.index { |message| message.equal?(from) }
      messages[index] = to if index
    end

    # Streaming still reports usage, so a streamed turn is billed like any other.
    def streamer
      return nil if @on_chunk.nil?

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

      return nil if send_back?(message)
      return STATUS_ANSWERED if @reply_is_answer

      return STATUS_STALLED if @reminders.positive?

      @reminders += 1
      @nudge.call(REMINDER)
      nil
    end

    # The first check that has something to say sends the reply back, and is never asked again this run.
    def send_back?(message)
      return false unless @reply_is_answer

      @checks.each do |check|
        said = check.call(message)
        next unless said

        @checks.delete(check)
        @nudge.call(said)
        return true
      end
      false
    end

    # The record's messages are rows. These are the ones the model sees.
    def messages = @chat.to_llm.messages

    def outcome(status) = Outcome.new(status: status, turns_used: @turns, spent_micros: @purse.spent)
  end
end
