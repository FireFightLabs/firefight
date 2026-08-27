module Mcp
  module Tools
    class DeleteWebhook < Base
      tool_name DELETE_WEBHOOK
      description "Delete an outbound webhook by id, along with its delivery history. Disabling it " \
                  "with upsert_webhook is the reversible move. If the call requires approval, " \
                  "retry the identical call with approval_id once approved. Docs: #{Docs::MCP_SERVER}"
      annotations(**DESTRUCTIVE)
      input_schema(
        properties: {
          id: { type: "string", description: "Id of the webhook to delete" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "id" ]
      )
      authorize_as Ability::Action::RESOURCE_WEBHOOKS, Ability::Action::ACTION_DELETE

      def self.perform(workspace:, args:)
        workspace.webhooks.find(args[:id].to_s).destroy!

        respond(id: args[:id].to_s, deleted: true)
      end
    end
  end
end
