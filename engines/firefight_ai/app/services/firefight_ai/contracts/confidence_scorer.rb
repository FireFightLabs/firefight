module FirefightAi
  module Contracts
    # Evidence in, named factors out. A low score has to say which factor is weak.
    module ConfidenceScorer
      Request = Data.define(:evidence, :self_assessment)
      Score = Data.define(:value, :factors)

      def score(request)
        raise NotImplementedError, "#{self.class.name} must implement score(request)"
      end
    end
  end
end
