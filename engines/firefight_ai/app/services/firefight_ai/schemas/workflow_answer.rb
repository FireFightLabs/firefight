module FirefightAi
  module Schemas
    class WorkflowAnswer < ::Schematist::Schema
      OK = "ok".freeze
      PROBLEM = "problem".freeze
      UNSURE = "unsure".freeze
      VERDICTS = [ OK, PROBLEM, UNSURE ].freeze

      description "Halon's judgement of the data a step of a workflow handed it, as a verdict, a summary and the fields it was asked for"

      string :verdict, enum: VERDICTS, description: "ok when the data shows nothing wrong for what was asked, problem when it shows something " \
                                                    "wrong, unsure when it cannot tell either way"
      string :summary, description: "Two or three plain sentences answering the question from the data, naming what in it shows that"
      array :fields, description: "One entry for each field the question asks for, in its order. Empty when it asks for none" do
        object do
          string :name, description: "The field's name, copied exactly"
          string :value, description: "Its value from the data, plain text. Empty when the data does not show it"
        end
      end
    end
  end
end
