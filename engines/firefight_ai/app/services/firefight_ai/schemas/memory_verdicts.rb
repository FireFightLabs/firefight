module FirefightAi
  module Schemas
    class MemoryVerdicts < ::Schematist::Schema
      SAME = "same".freeze
      CONTRADICTS = "contradicts".freeze
      UNRELATED = "unrelated".freeze
      VERDICTS = [ SAME, CONTRADICTS, UNRELATED ].freeze

      description "For each fact already remembered, whether the new fact says the same thing, contradicts it or is about something else"

      array :verdicts do
        object do
          integer :number, description: "The remembered fact's number, copied exactly"
          string :verdict, enum: VERDICTS, description: "same when both say one thing in other words, contradicts when both cannot be true at once, " \
                                                        "unrelated otherwise, including when the new fact only adds something"
        end
      end
    end
  end
end
