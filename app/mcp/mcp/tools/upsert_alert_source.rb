module Mcp
  module Tools
    class UpsertAlertSource < Base
      tool_name UPSERT_ALERT_SOURCE
      description "Create or change an alert source, which is the endpoint a monitoring tool posts " \
                  "alerts to. Pass slug to change an existing one, or leave it out to create. The " \
                  "slug is the endpoint path, fixed once the source exists so whatever is already " \
                  "posting keeps working. The signing secret is never returned here, copy it from " \
                  "the dashboard. Call get_workspace_config for what this workspace has today. If " \
                  "the call requires approval, retry the identical call with approval_id once " \
                  "approved. Docs: #{Docs::ALERTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          slug: { type: "string", description: "Endpoint path of the one to change; omit to create" },
          name: { type: "string", description: "What responders see on an alert. Required when creating" },
          provider: {
            type: "string",
            enum: AlertSource::PROVIDERS,
            description: "Which payload shape it sends. Fixed at creation"
          },
          enabled: { type: "boolean", description: "false stops it accepting alerts without deleting it" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )
      upserts Ability::Action::RESOURCE_ALERTS,
        scope: ->(workspace) { workspace.alert_sources },
        key: :slug, column: :endpoint_path

      def self.perform(workspace:, args:)
        source = upsert_target(workspace, args)

        if source
          source.update!({ name: args[:name], enabled: args[:enabled] }.compact)
        else
          source = workspace.alert_sources.create!(
            name: args[:name],
            provider: args[:provider].presence || AlertSource::PROVIDER_GENERIC
          )
        end

        respond(summary(source.reload))
      end

      def self.summary(source)
        {
          slug: source.endpoint_path,
          name: source.name,
          provider: source.provider,
          enabled: source.enabled
        }
      end
    end
  end
end
