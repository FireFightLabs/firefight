module FirefightAi
  module Schemas
    # PermissionDecision when nobody can be asked, so the judge must choose.
    class PermissionDecisionAlone < ::Schematist::Schema
      description "Whether a coding agent may go on with a step it asked permission for, and why, decided without asking anyone"

      string :decision, enum: FirefightAi::PermissionJudge::ALONE,
                        description: "allow to let it go on, or stop to refuse the step"
      string :reason, description: "Why, in one or two plain sentences about what the agent was doing, which a person reads on the change's step"
    end
  end
end
