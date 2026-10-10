module FirefightAi
  class AgentLoop
    # What a run has spent, in micros. Helpers working beside the loop spend from the same purse on their own threads, so
    # their model calls count against the budget the loop stops on.
    class Purse
      def initialize(spent_micros = 0)
        @spent_micros = spent_micros
        @lock = Mutex.new
      end

      def add(micros)
        @lock.synchronize { @spent_micros += micros.to_i }
      end

      def spent = @lock.synchronize { @spent_micros }

      # What is left of a cap set in cents, never below zero.
      def left(max_spend_cents) = [ (max_spend_cents * MICROS_PER_CENT) - spent, 0 ].max
    end
  end
end
