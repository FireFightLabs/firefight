module FirefightAi
  module Schemas
    class ChatLessons < ::Schematist::Schema
      LESSONS_KEY = "lessons".freeze

      description "What a finished chat with Halon taught about the team's setup"

      array :lessons do
        object do
          string :fact, description: "One lasting fact about the setup in one plain sentence, such as 'Checkout keeps sessions in the firefight-prod database'"
          string :about, description: "The name of the service, catalog entry or resource the fact is about, as the chat names it, or empty when it is about the whole workspace"
          number :confidence, description: "How sure the chat makes you, between 0 and 1"
        end
      end
    end
  end
end
