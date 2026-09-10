module Mcp
  module Tools
    class TestWebhook < Base
      # Each call queues another delivery to somebody else's server, so this is
      # neither idempotent nor closed-world.
      SENDS = {
        read_only_hint: false, destructive_hint: false,
        idempotent_hint: false, open_world_hint: true
      }.freeze

      tool_name TEST_WEBHOOK
      description "Send a test delivery to an outbound webhook, to confirm the endpoint receives " \
                  "and verifies what Firefight sends before relying on it. It replays the newest " \
                  "event in this workspace the webhook subscribes to, signed the way a live " \
                  "delivery is. The delivery is queued and the response names it. Its outcome, " \
                  "response code and timing are on the webhook's deliveries list in the " \
                  "dashboard. Refused while the webhook is disabled or nothing it subscribes to " \
                  "has happened yet. If the call requires approval, retry the identical call " \
                  "with approval_id once approved. Docs: #{Docs::WEBHOOKS}"
      annotations(**SENDS)
      input_schema(
        properties: {
          id: { type: "string", description: "Id of the webhook, from get_workspace_config" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "id" ]
      )
      authorize_as Ability::Action::RESOURCE_WEBHOOKS, Ability::Action::ACTION_UPDATE

      def self.perform(workspace:, args:)
        webhook = workspace.webhooks.find(args[:id].to_s)
        delivery = webhook.queue_test_delivery!

        respond(
          delivery_id: delivery.id,
          webhook_id: webhook.id,
          url: webhook.url,
          event_type: delivery.event_type,
          state: delivery.state
        )
      rescue Webhook::TestBlocked => e
        Mcp::ToolDispatcher.error_response(e.message)
      end
    end
  end
end
