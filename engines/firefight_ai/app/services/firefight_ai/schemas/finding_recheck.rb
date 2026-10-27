module FirefightAi
  module Schemas
    class FindingRecheck < ::Schematist::Schema
      description "Whether a push to a pull request fixed one problem a review found in it"

      string :outcome, enum: %w[fixed not_fixed unclear],
                       description: "fixed when the code as it stands now no longer has the problem, not_fixed when it still does, unclear only when the material shown cannot tell"
      string :words, description: "One or two short plain sentences for the thread on the pull request, naming the file and what the new code does about the problem. No praise and no instruction to anyone"
    end
  end
end
