module FirefightAi
  module Contracts
    # A question with a scope in, one answer plus references out. Never raw tool output.
    module Specialist
      Question = Data.define(:text, :entities, :window, :hypothesis_id, :max_turns)
      Answer = Data.define(:text, :evidence)

      def ask(question)
        raise NotImplementedError, "#{self.class.name} must implement ask(question)"
      end
    end
  end
end
