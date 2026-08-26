module Mcp
  module Tools
    class UpsertIncidentRole < Base
      include ConfiguresOption

      tool_name UPSERT_INCIDENT_ROLE
      configures_option IncidentRole,
        resource: Ability::Action::RESOURCE_INCIDENT_ROLES,
        guidance: "A role holds one person at a time. "

      def self.perform(workspace:, args:)
        ConfiguresOption.upsert(self, workspace, args)
      end
    end
  end
end
