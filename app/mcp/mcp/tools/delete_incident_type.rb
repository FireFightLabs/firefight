module Mcp
  module Tools
    class DeleteIncidentType < Base
      include ConfiguresOption

      tool_name DELETE_INCIDENT_TYPE
      deletes_option IncidentType, resource: Ability::Action::RESOURCE_INCIDENT_TYPES

      def self.perform(workspace:, args:)
        ConfiguresOption.destroy(self, workspace, args)
      end
    end
  end
end
