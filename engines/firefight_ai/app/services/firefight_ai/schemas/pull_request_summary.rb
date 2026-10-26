module FirefightAi
  module Schemas
    class PullRequestSummary < ::Schematist::Schema
      LOW = "low".freeze
      MEDIUM = "medium".freeze
      HIGH = "high".freeze
      RISKS = [ LOW, MEDIUM, HIGH ].freeze

      description "What a pull request does and how risky it is to merge"

      string :summary, description: "One short paragraph on what the pull request does, for someone who has not read it, naming the parts of the system it changes"
      string :risk, enum: RISKS,
                    description: "high when merging it as it is would likely cause an incident, medium when it holds a real problem normal use will hit or reaches much of what runs, low otherwise"
      string :risk_reason, description: "One plain sentence on why, naming the finding or the reach behind it"
    end
  end
end
