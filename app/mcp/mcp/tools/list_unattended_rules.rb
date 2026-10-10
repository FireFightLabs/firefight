module Mcp
  module Tools
    class ListUnattendedRules < Base
      tool_name LIST_UNATTENDED_RULES
      description "Every unattended rule in this workspace: a change Halon may make on its own (a rollback or restart of one " \
                  "resource on the map) when an alert started its investigation and a fresh reading of a metric is above a " \
                  "threshold. Each says why it cannot act yet, when it cannot, and how many times Halon acted under it. " \
                  "Authorizes as permissions, which is admin-only. Docs: #{Docs::ON_CALL}"
      annotations(**READ_ONLY)
      input_schema(properties: {}, required: [])
      authorize_as Ability::Action::RESOURCE_PERMISSIONS

      def self.perform(workspace:, args:)
        rules = workspace.unattended_rules.with_usage_counts.includes(:resource, :created_by).order(:created_at)
        respond(unattended_rules: rules.map(&:payload))
      end
    end
  end
end
