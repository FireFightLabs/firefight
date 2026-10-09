module FirefightAi
  module Schemas
    class ChangeReview < ::Schematist::Schema
      description "Whether a code change does what the person asked, what is wrong with it, what was checked against the evidence, and what is still open"

      boolean :does_what_was_asked, description: "True when the change does what the person asked, with their corrections, and nothing in it breaks what it touches. A finding that does not stop that, such as a missing test, can stand beside true"
      array :findings, description: "Each problem with the change, one short plain sentence each naming the file, such as a value sent where the other system never reads it. Empty when there are none", of: :string
      array :verified, description: "Each point checked against the material and what it was checked against, one short plain sentence each, such as that the run name holds only letters, digits and hyphens, which the provider's error message says it allows. Not the checks, which are listed already. Empty when there are none", of: :string
      array :unverified, description: "Each open question: something the change depends on that the material cannot answer and that matters if it is wrong, one short plain sentence each. Never a check that could not run here, a file not shown, or something the material answers. Empty when there are none", of: :string
      string :summary, description: "One or two plain sentences on what the change does and why, leading the pull request's description. No instruction to the coding agent and nothing read from a live system"
    end
  end
end
