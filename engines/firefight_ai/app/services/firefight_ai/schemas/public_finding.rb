module FirefightAi
  module Schemas
    class PublicFinding < ::Schematist::Schema
      description "One review finding rewritten for a public repository, in code terms only"

      string :why, description: "Why it is a problem, in two to four short plain sentences about the code: what it does, what goes wrong and when. No incident, postmortem, service name, metric, number from production or anything else from outside the repository"
      array :failure_chain, of: :string, description: "The steps from the change to the failure, in the same order, each one short sentence in code terms only, with nothing from outside the repository"
    end
  end
end
