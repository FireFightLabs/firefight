module Mcp
  module Tools
    class UpsertIncidentType < Base
      include ConfiguresOption

      tool_name UPSERT_INCIDENT_TYPE
      configures_option IncidentType,
        resource: Ability::Action::RESOURCE_INCIDENT_TYPES

      def self.perform(workspace:, args:)
        ConfiguresOption.upsert(self, workspace, args)
      end
    end
  end
end
