module Mcp
  module Tools
    class ListAllowances < Base
      tool_name FirefightTools::LIST_ALLOWANCES
      description "Every entry of what Halon may do without asking in a person's chat: a risky change through a capability " \
                  "(rollback, restart or scale) or through one connection's tool, kept to a connection or an environment when one " \
                  "is named. Safe changes run without asking while the workspace lets them, whatever this list holds. Each entry " \
                  "says how many changes Halon made under it. Authorizes as permissions, which is admin-only. Docs: #{Docs::WITHOUT_ASKING}"
      annotations(**READ_ONLY)
      input_schema(properties: {}, required: [])
      authorize_as Ability::Action::RESOURCE_PERMISSIONS

      def self.perform(workspace:, args:)
        allowances = workspace.allowances.with_usage_counts.includes(:environment, :created_by, :integration, action: :source).order(:created_at)
        respond(allowances: allowances.map(&:payload), safe_changes_without_asking: workspace.safe_changes_without_asking?)
      end
    end
  end
end
