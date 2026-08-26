module Mcp
  module Tools
    class UpsertStatus < Base
      include ConfiguresOption

      tool_name UPSERT_STATUS
      configures_option IncidentStatus,
        resource: Ability::Action::RESOURCE_STATUSES,
        extra: { lifecycle_stage: { type: "string", enum: IncidentLifecycleStage::KEYS, description: "Which stage this status belongs to. Required when creating" } },
        guidance: "A status belongs to one lifecycle stage, which decides whether it means the incident is live, closed or canceled. ",
        prepare: ->(args) {
          next {} if args[:lifecycle_stage].blank?

          { incident_lifecycle_stage: IncidentLifecycleStage.find_by!(key: args[:lifecycle_stage].to_s) }
        }

      def self.perform(workspace:, args:)
        ConfiguresOption.upsert(self, workspace, args)
      end
    end
  end
end
