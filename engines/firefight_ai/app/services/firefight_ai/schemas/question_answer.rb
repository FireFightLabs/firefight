module FirefightAi
  module Schemas
    class QuestionAnswer < ::Schematist::Schema
      description "Whether what Halon already knows answers a coding agent's question, and the answer"

      boolean :answered, description: "True only when the person's own words or the evidence settle the question, never from a guess"
      string :option, description: "The label of the option the answer picks, copied exactly, or empty when it picks none"
      string :answer, description: "The answer in one to three plain sentences, naming where it comes from. Empty when answered is false"
    end
  end
end
