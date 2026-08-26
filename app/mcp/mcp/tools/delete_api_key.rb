module Mcp
  module Tools
    class DeleteApiKey < Base
      tool_name DELETE_API_KEY
      description "Delete a service key by prefix. Anything presenting it stops working " \
                  "immediately. Setting active to false with upsert_api_key is the reversible " \
                  "move. Authorizes as api_keys, which is admin-only. Docs: #{Docs::MCP_SERVER}"
      annotations(**DESTRUCTIVE)
      input_schema(
        properties: {
          prefix: { type: "string", description: "Prefix of the key to delete" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "prefix" ]
      )
      authorize_as Ability::Action::RESOURCE_API_KEYS, Ability::Action::ACTION_DELETE

      def self.perform(workspace:, args:)
        key = workspace.api_keys.where(deleted_at: nil).service.find_by!(token_prefix: args[:prefix].to_s)
        key.soft_delete!

        respond(prefix: args[:prefix].to_s, deleted: true)
      end
    end
  end
end
