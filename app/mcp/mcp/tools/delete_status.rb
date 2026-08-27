module Mcp
  module Tools
    class DeleteStatus < Base
      include ConfiguresOption

      tool_name DELETE_STATUS
      deletes_option IncidentStatus, resource: Ability::Action::RESOURCE_STATUSES

      def self.perform(workspace:, args:)
        ConfiguresOption.destroy(self, workspace, args)
      end
    end
  end
end
