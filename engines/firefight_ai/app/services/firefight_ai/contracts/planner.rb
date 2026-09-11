module FirefightAi
  module Contracts
    # Seed pack in, the theories a run will pursue out.
    module Planner
      Request = Data.define(:seed_pack, :max_turns, :max_tokens)
      Theory = Data.define(:assertion, :specialist, :first_question, :max_turns)

      def plan(request)
        raise NotImplementedError, "#{self.class.name} must implement plan(request)"
      end
    end
  end
end
