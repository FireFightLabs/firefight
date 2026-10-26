module FirefightAi
  module Schemas
    class PullRequestLesson < ::Schematist::Schema
      STATED = "stated_reason".freeze
      REPEATED = "repeated_cause".freeze
      NONE = "none".freeze
      BASES = [ STATED, REPEATED, NONE ].freeze

      description "What a person's handling of a pull request Halon opened teaches about changes to its repository"

      string :lesson, description: "One plain sentence Halon should follow in later changes to this repository, or empty when there is no lesson"
      string :basis, enum: BASES, description: "stated_reason when the person said why, repeated_cause when an earlier pull request listed shows the same cause, none otherwise"
      number :confidence, description: "How sure the material makes you, between 0 and 1"
    end
  end
end
