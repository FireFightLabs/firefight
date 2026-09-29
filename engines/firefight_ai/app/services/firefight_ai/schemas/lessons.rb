module FirefightAi
  module Schemas
    class Lessons < ::Schematist::Schema
      LESSONS_KEY = "lessons".freeze
      VERDICTS_KEY = "verdicts".freeze
      AGREES = "agrees".freeze
      CONTRADICTS = "contradicts".freeze
      SILENT = "silent".freeze

      description "What an ended incident taught about the setup, and whether the sources agree with what was learned before"

      array :lessons do
        object do
          string :fact, description: "One lasting fact about the setup in one plain sentence, such as 'Checkout keeps sessions in the firefight-prod database'"
          string :about, description: "The name of what the fact is about, copied from the list given, or empty when none fits"
          number :confidence, description: "How sure the sources make you, between 0 and 1"
        end
      end

      array :verdicts do
        object do
          string :memory_id, description: "The id of a lesson learned before, copied from the list given"
          string :verdict, enum: [ AGREES, CONTRADICTS, SILENT ], description: "Whether the sources agree with it, contradict it, or say nothing about it"
          string :correction, description: "When they contradict it, what is right instead, in one plain sentence, otherwise empty"
        end
      end
    end
  end
end
