module FirefightAi
  module Schemas
    # What a pull request does and how risky it is to merge. The risks are the app's, handed in, so the engine keeps no
    # copy of them.
    module PullRequestSummary
      def self.for(risks)
        Class.new(::Schematist::Schema) do
          description "What a pull request does and how risky it is to merge"

          string :summary, description: "One short paragraph on what the pull request does, for someone who has not read it, naming the parts of the system it changes"
          string :risk, enum: risks,
                        description: "high when merging it as it is would likely cause an incident, medium when it holds a real problem normal use will hit or reaches much of what runs, low otherwise"
          string :risk_reason, description: "One plain sentence on why, naming the finding or the reach behind it"
        end
      end
    end
  end
end
