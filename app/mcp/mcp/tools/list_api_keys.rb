module Mcp
  module Tools
    class ListApiKeys < Base
      tool_name LIST_API_KEYS
      description "Every service key in this workspace, with the abilities it holds and when it was " \
                  "last used. Personal tokens are left out: they belong to the person who minted " \
                  "them, not to the workspace. Authorizes as api_keys, which is admin-only and " \
                  "cannot be granted to a machine. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      input_schema(properties: {}, required: [])
      authorize_as Ability::Action::RESOURCE_API_KEYS

      def self.perform(workspace:, args:)
        keys = workspace.api_keys.where(deleted_at: nil).service.ordered

        respond(api_keys: keys.map { |key| ApiKeyPayloads.summary(key) })
      end
    end
  end
end
