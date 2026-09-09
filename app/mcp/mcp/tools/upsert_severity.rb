module Mcp
  module Tools
    class UpsertSeverity < Base
      include ConfiguresOption

      tool_name UPSERT_SEVERITY
      configures_option IncidentSeverity,
        resource: Ability::Action::RESOURCE_SEVERITIES,
        guidance: "Position is how severe it is, first being the most severe, so a new SEV0 takes " \
                  "position 1. The rank in the response is derived from that order, higher meaning " \
                  "more severe, and cannot be set directly. "

      def self.perform(workspace:, args:)
        ConfiguresOption.upsert(self, workspace, args)
      end
    end
  end
end
