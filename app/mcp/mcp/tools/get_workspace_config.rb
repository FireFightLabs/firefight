module Mcp
  module Tools
    # One read behind every configuration tool. An agent asked to change how a
    # workspace is set up needs the slugs before it can name anything, and
    # seven separate list tools would be seven calls to answer one question.
    class GetWorkspaceConfig < Base
      tool_name GET_WORKSPACE_CONFIG
      authorize_as Ability::Action::RESOURCE_INCIDENTS
      description "Everything about how this workspace is configured, in one call: its severities, " \
                  "statuses with their lifecycle stage, incident types, incident roles, alert " \
                  "sources and webhooks. Slugs from here are what the upsert and delete tools " \
                  "take. Disabled entries are included and marked, since disabling is how a list " \
                  "retires something without breaking the incidents pointing at it. " \
                  "Docs: #{Docs::INCIDENTS}"
      annotations(**READ_ONLY)
      input_schema(properties: {}, required: [])

      def self.perform(workspace:, args:)
        respond(
          severities: options(workspace.incident_severities),
          statuses: options(workspace.incident_statuses.includes(:incident_lifecycle_stage)),
          incident_types: options(workspace.incident_types),
          incident_roles: options(workspace.incident_roles),
          alert_sources: alert_sources(workspace),
          webhooks: webhooks(workspace)
        )
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
