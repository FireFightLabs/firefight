module FirefightAi
  module Schemas
    class PermissionDecision < ::Schematist::Schema
      description "Whether a coding agent may go on with a step it asked permission for, and why"

      string :decision, enum: FirefightAi::PermissionJudge::DECISIONS,
                        description: "allow to let it go on, stop to refuse the step, or ask when the person should choose"
      string :lean, enum: FirefightAi::PermissionJudge::ALONE,
                    description: "With ask, the way you lean, which the person sees as your recommendation and which stands if nobody answers in time"
      string :reason, description: "Why, in one or two plain sentences about what the agent was doing, which a person reads on the change's step"
    end
  end
end
