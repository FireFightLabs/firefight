module Mcp
  module Tools
    class UpsertWebhook < Base
      tool_name UPSERT_WEBHOOK
      description "Create or change an outbound webhook, which posts incident events to a URL you " \
                  "own. Pass id to change an existing one, or leave it out to create. Sending " \
                  "subscribed_events replaces the set rather than adding to it, so read the " \
                  "current one from get_workspace_config first. The signing secret is never " \
                  "returned here, copy it from the dashboard. If the call requires approval, retry " \
                  "the identical call with approval_id once approved. Docs: #{Docs::MCP_SERVER}"
      annotations(**WRITE)
      input_schema(
        properties: {
          id: { type: "string", description: "Id of the one to change; omit to create" },
          name: { type: "string", description: "What it is for, in one line. Required when creating" },
          url: { type: "string", description: "Where the events are posted. Required when creating" },
          subscribed_events: {
            type: "array",
            items: { type: "string", enum: Webhook::SUBSCRIBABLE_EVENTS },
            description: "Which events it receives. Replaces the current set"
          },
          enabled: { type: "boolean", description: "false stops deliveries without deleting it" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )
      upserts Ability::Action::RESOURCE_WEBHOOKS,
        scope: ->(workspace) { workspace.webhooks },
        key: :id

      def self.perform(workspace:, args:)
        webhook = upsert_target(workspace, args)
        attributes = {
          name: args[:name],
          url: args[:url],
          subscribed_events: args[:subscribed_events]
        }.compact

        if webhook
          webhook.update!(attributes)
        else
          webhook = workspace.webhooks.create!(attributes)
        end

        toggle(webhook, args[:enabled]) unless args[:enabled].nil?

        respond(summary(webhook.reload))
      end

      def self.toggle(webhook, enabled)
        enabled ? webhook.activate! : webhook.deactivate!
      end

      def self.summary(webhook)
        {
          id: webhook.id,
          name: webhook.name,
          url: webhook.url,
          subscribed_events: webhook.subscribed_events,
          enabled: webhook.active?
        }
      end
    end
  end
end
