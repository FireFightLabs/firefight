module Mcp
  module Tools
    class DeleteIncidentRole < Base
      include ConfiguresOption

      tool_name FirefightTools::DELETE_INCIDENT_ROLE
      deletes_option IncidentRole, resource: Ability::Action::RESOURCE_INCIDENT_ROLES

      def self.perform(workspace:, args:)
        ConfiguresOption.destroy(self, workspace, args)
      end
    end
  end
end
