module Mcp
  module Tools
    # An agent needs the slugs before it can name anything, and separate list
    # tools would be several calls to answer one question.
    class GetWorkspaceConfig < Base
      tool_name GET_WORKSPACE_CONFIG
      authorize_as Ability::Action::RESOURCE_INCIDENTS
      description "Everything about how this workspace is configured, in one call: its severities, " \
                  "statuses with their lifecycle stage, incident types, incident roles, alert " \
                  "sources, webhooks, and the workspace settings when you may read them. Slugs from here are what the upsert and delete tools " \
                  "take. Disabled entries are included and marked, since disabling is how a list " \
                  "retires something without breaking the incidents pointing at it. " \
                  "Docs: #{Docs::INCIDENTS}"
      annotations(**READ_ONLY)
      input_schema(properties: {}, required: [])

      def self.perform_with_principal(workspace:, principal:, args:)
        respond(
          severities: options(workspace.incident_severities),
          statuses: options(workspace.incident_statuses.includes(:incident_lifecycle_stage)),
          incident_types: options(workspace.incident_types),
          incident_roles: options(workspace.incident_roles),
          alert_sources: alert_sources(workspace),
          webhooks: webhooks(workspace),
          **settings_for(workspace, principal)
        )
      end

      # The settings page is for admins, so they are shown here on the same permission it asks for.
      def self.settings_for(workspace, principal)
        key = Ability::Action.system_key(Ability::Action::RESOURCE_WORKSPACE, Ability::Action::ACTION_READ)
        return {} unless principal.permitted_to?(Ability::Action.lookup(key, workspace), workspace)

        { settings: workspace.settings }
      end

      def self.options(scope)
        scope.ordered.map { |option| ConfiguresOption.summary(option) }
      end

      def self.alert_sources(workspace)
        workspace.alert_sources.order(:name).map do |source|
          { slug: source.endpoint_path, name: source.name, provider: source.provider }
        end
      end

      def self.webhooks(workspace)
        workspace.webhooks.ordered.map do |webhook|
          { id: webhook.id, name: webhook.name, url: webhook.url, events: webhook.subscribed_events, enabled: webhook.active? }
        end
      end
    end
  end
end
