module FirefightAi
  module Contracts
    # One theory, pursued until it is supported, refuted or out of budget.
    module BranchRunner
      Request = Data.define(:hypothesis, :blackboard, :tools, :max_turns)
      Outcome = Data.define(:status, :confidence, :evidence, :steps)

      def run(request)
        raise NotImplementedError, "#{self.class.name} must implement run(request)"
      end
    end
  end
end
