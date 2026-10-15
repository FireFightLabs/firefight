module FirefightAi
  class AgentLoop
    # How the loop's chat runs the tool calls of one model step. RubyLLM runs them all at once on threads of their own
    # (concurrency: :threads) and saves each result as it lands. Here RubyLLM's own runner (Chat::ToolConcurrency) still
    # runs them, each thread with its own unit of work and the caller's trace, but only calls that may run together do,
    # and every result is saved in the order the model asked.
    #
    # A call runs beside others only when its tool says it only reads (concurrent_read?) and needs nobody's decision.
    # Neighbouring such calls run together, each tool at most once in a group, since a tool keeps what one call found on
    # itself while it runs. Any other call, a change, one put to the person, one that opens tools or ends the run, runs
    # on its own once every call asked before it has run and its result is saved, as every call did before. So a change
    # still sees the reads asked before it, and a call that opens tools has done so before the next one is looked up.
    #
    # A group is announced (before_tool_call) on the calling thread in the order asked, and each result is saved there as
    # soon as every call asked before it is saved. A call that raised saves nothing asked after it, and a stop saves
    # nothing more at all, as a run of one call at a time would not have got that far.
    module ToolsTogether
      Group = Data.define(:together, :calls)

      # The calls of a step as they run, in the order asked.
      def self.groups(tool_calls, tools)
        tool_calls.each_with_object([]) do |(id, tool_call), groups|
          together = together?(tools[tool_call.name.to_sym])
          last = groups.last
          if together && last&.together && last.calls.each_value.none? { |asked| asked.name == tool_call.name }
            last.calls[id] = tool_call
          else
            groups << Group.new(together: together, calls: { id => tool_call })
          end
        end
      end

      def self.together?(tool)
        tool.respond_to?(:concurrent_read?) && tool.concurrent_read? && !tool.requires_approval?
      end

      private

      def handle_concurrent_tool_calls(tool_calls)
        ToolsTogether.groups(tool_calls, tools).each do |group|
          group.calls.size == 1 ? handle_sequential_tool_calls(group.calls) : run_together(group.calls)
        end
      end

      def run_together(tool_calls)
        raise_if_cancelled!
        tool_calls.each_value { |tool_call| run_callbacks(:before_tool_call, tool_call) }
        saving = InOrder.new(tool_calls.keys) { |id, result| save_result(tool_calls[id], result) }
        self.class.const_get(:ToolConcurrency).run(concurrency, tool_calls, on_result: saving.method(:answered)) do |tool_call|
          run_called(tool_call, saving)
        end
      end

      # RubyLLM's own steps for one call, less its announcement, which run_together made in order.
      def run_called(tool_call, saving)
        raise_if_cancelled!
        result = execute_tool(tool_call)
        return result if paused?(result)

        raise_if_cancelled!
        run_callbacks(:after_tool_result, result)
        result
      rescue RubyLLM::CancelledError
        saving.stopped!
        raise
      rescue StandardError
        saving.failed!(tool_call.id)
        raise
      end

      def save_result(tool_call, result)
        return if paused?(result)

        raise_if_cancelled!
        run_callbacks(:before_message)
        add_tool_result_message(tool_call, result)
      end

      def paused?(result) = result.equal?(self.class.const_get(:PAUSED))

      # Saves each result once every call asked before it is saved. Results arrive on the calling thread, and a call's
      # failure is told from its own thread before its result would have arrived.
      class InOrder
        def initialize(order, &save)
          @order = order
          @save = save
          @answered = {}
          @next = 0
          @last = order.size
          @lock = Mutex.new
        end

        # Nothing more is saved.
        def stopped! = @lock.synchronize { @last = 0 }

        # Nothing from this call on is saved.
        def failed!(id) = @lock.synchronize { @last = [ @last, @order.index(id) || @last ].min }

        def answered(tool_call, result)
          @answered[tool_call.id] = result
          while (id = due)
            @save.call(id, @answered.delete(id))
          end
        rescue RubyLLM::CancelledError
          stopped!
          raise
        end

        private

        def due
          @lock.synchronize do
            id = @order[@next]
            next unless @next < @last && @answered.key?(id)

            @next += 1
            id
          end
        end
      end
    end
  end
end
