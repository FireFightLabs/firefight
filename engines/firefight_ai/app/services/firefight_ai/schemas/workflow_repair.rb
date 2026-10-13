module FirefightAi
  module Schemas
    class WorkflowRepair < ::Schematist::Schema
      description "A fix to the settings of the one step of a workflow that failed, when its settings caused the failure"

      boolean :fixable, description: "True only when changing the failed step's own settings would stop it failing this way, never for an outage, a missing grant or a system that was down"
      string :reason, description: "One or two plain sentences on why the step failed and what the change does. Empty when fixable is false"
      string :config_json, description: "A JSON object of only the settings to change and their new values, such as {\"arguments\": {\"resource\": \"web\"}}. Empty when fixable is false"
    end
  end
end
