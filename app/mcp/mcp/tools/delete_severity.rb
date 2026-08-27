module Mcp
  module Tools
    class DeleteSeverity < Base
      include ConfiguresOption

      tool_name DELETE_SEVERITY
      deletes_option IncidentSeverity, resource: Ability::Action::RESOURCE_SEVERITIES

      def self.perform(workspace:, args:)
        ConfiguresOption.destroy(self, workspace, args)
      end
    end
  end
end
