module FirefightAi
  module Schemas
    class CitationCheck < ::Schematist::Schema
      # The check reads the response by this key.
      ROOT_KEY = "claims".freeze

      description "For each claim of a finding, whether the tool results it cites show it"

      array :claims do
        object do
          integer :number, description: "The claim's number, copied exactly"
          boolean :shown, description: "True when the cited results state the claim or it follows directly from what they state"
          string :reason,
                 description: "One sentence on what the cited results say that shows it or does not, e.g. " \
                              "'step 4 shows the method is called but no step shows where it is defined'"
        end
      end
    end
  end
end
