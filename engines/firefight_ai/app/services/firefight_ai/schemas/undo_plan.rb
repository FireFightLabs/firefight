module FirefightAi
  module Schemas
    class UndoPlan < ::Schematist::Schema
      STEPS_KEY = "steps".freeze

      description "The steps that reverse a fix that was applied, in the order to run them"

      string :summary, description: "What undoing puts back, in one plain sentence"
      string :verify, description: "How to tell everything is back as it was, in one plain sentence"
      array :steps do
        object do
          string :kind, enum: %w[pull_request action manual], description: "pull_request for a code change, action for a tool call, manual for a person"
          string :description, description: "What the step puts back, in one plain sentence"
          string :repository, description: "For a pull_request, the repository in owner/name form, otherwise empty"
          string :tool, description: "For an action, the tool to call, copied from the list given, otherwise empty"
          string :arguments, description: "For an action, the tool's arguments as a JSON object, otherwise empty"
          string :missing, description: "For a manual step, what Firefight would need to do it itself, otherwise empty"
          array :depends_on, description: "Earlier steps of this undo it must wait for, by number" do
            integer
          end
        end
      end
    end
  end
end
