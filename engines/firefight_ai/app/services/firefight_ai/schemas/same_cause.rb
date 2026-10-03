module FirefightAi
  module Schemas
    class SameCause < ::Schematist::Schema
      SAME = "same".freeze
      DIFFERENT = "different".freeze
      UNCLEAR = "unclear".freeze

      description "Whether two answers to the same incident name the same cause"

      string :verdict, enum: [ SAME, DIFFERENT, UNCLEAR ], description: "same when both name one cause, different when they name different causes, unclear when either names none"
      string :reason, description: "Why, in one plain sentence naming the cause each answer gives"
    end
  end
end
