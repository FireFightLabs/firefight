module Mcp
  module Tools
    class UpsertSeverity < Base
      include ConfiguresOption

      tool_name UPSERT_SEVERITY
      configures_option IncidentSeverity,
        resource: Ability::Action::RESOURCE_SEVERITIES,
        extra: { rank: { type: "integer", description: "How grave this is. 1 is the most severe, and the number orders the list" } },
        guidance: "Rank is what orders them, so a new SEV0 takes rank 1. ",
        prepare: ->(args) { args[:rank].present? ? { rank: args[:rank] } : {} }

      def self.perform(workspace:, args:)
        ConfiguresOption.upsert(self, workspace, args)
      end
    end
  end
end
