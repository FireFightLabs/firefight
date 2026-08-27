module Mcp
  module Tools
    class UpsertApiKey < Base
      tool_name UPSERT_API_KEY
      description "Create or change a service key, which is a credential for automation with " \
                  "nothing to say on a timeline. Use upsert_agent instead for an AI that takes " \
                  "part in incidents under its own name. Pass prefix to change an existing key, or " \
                  "leave it out to create. Creating returns the token once and never again. " \
                  "Sending permissions replaces the set rather than adding to it, so read the " \
                  "current one from list_api_keys first. Authorizes as api_keys, which is " \
                  "admin-only and cannot be granted to a machine. Docs: #{Docs::MCP_SERVER}"
      annotations(**WRITE)
      input_schema(
        properties: {
          prefix: { type: "string", description: "Prefix of the key to change; omit to create" },
          name: { type: "string", description: "What it is for. Required when creating" },
          permissions: {
            type: "object",
            description: "Resource to actions, e.g. { \"incidents\": [\"read\", \"create\"] }. Replaces the current set"
          },
          active: { type: "boolean", description: "false stops it authenticating without deleting it" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )
      upserts Ability::Action::RESOURCE_API_KEYS,
        scope: ->(workspace) { workspace.api_keys.where(deleted_at: nil).service },
        key: :prefix, column: :token_prefix

      def self.perform_with_principal(workspace:, principal:, args:)
        key = upsert_target(workspace, args)
        return respond(ApiKeyPayloads.summary(update(key, args))) if key

        key, token = create(workspace, principal, args)
        respond(ApiKeyPayloads.summary(key).merge(token: token))
      end

      def self.create(workspace, principal, args)
        ActiveRecord::Base.transaction do
          key, token = ApiKey.create_with_token!(
            workspace: workspace,
            created_by: AgentPayloads.creator_for(principal),
            name: args[:name]
          )
          key.replace_permissions!(args[:permissions].to_h) if args[:permissions].present?
          [ key.reload, token ]
        end
      end
      private_class_method :create

      def self.update(key, args)
        ActiveRecord::Base.transaction do
          key.update!({ name: args[:name], active: args[:active] }.compact)
          key.replace_permissions!(args[:permissions].to_h) if args[:permissions].present?
        end
        key.reload
      end
      private_class_method :update
    end
  end
end
