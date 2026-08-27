module Mcp
  module Tools
    class RevokeAgentToken < Base
      tool_name REVOKE_AGENT_TOKEN
      description "Revoke one of an agent's tokens, named by the prefix get_workspace_config and " \
                  "the rotate call report. It stops working immediately, and the agent keeps its " \
                  "name, its abilities and its history because those belong to the agent rather " \
                  "than to the secret. Authorizes as permissions, which is admin-only. " \
                  "Docs: #{Docs::PERMISSIONS}"
      annotations(**DESTRUCTIVE)
      input_schema(
        properties: {
          slug: { type: "string", description: "Slug of the agent the token belongs to" },
          token_prefix: { type: "string", description: "The token's prefix, from list_agents" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "slug", "token_prefix" ]
      )
      authorize_as Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_DELETE

      def self.perform(workspace:, args:)
        agent = workspace.agents.find_by!(slug: args[:slug].to_s)
        token = agent.live_api_keys.find { |key| key.token_prefix == args[:token_prefix].to_s }
        raise ActiveRecord::RecordNotFound unless token

        token.soft_delete!

        respond(AgentPayloads.summary(agent.reload).merge(revoked: args[:token_prefix].to_s))
      end
    end
  end
end
