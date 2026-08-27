module Mcp
  module Tools
    class RotateAgentToken < Base
      tool_name ROTATE_AGENT_TOKEN
      description "Issue a new token for an agent. The old one keeps working, so the agent stays up " \
                  "while its configuration is updated, and revoking the old one is a separate " \
                  "deliberate step with revoke_agent_token. The new token is returned once and " \
                  "never again. Authorizes as permissions, which is admin-only. " \
                  "Docs: #{Docs::PERMISSIONS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          slug: { type: "string", description: "Slug of the agent to issue a token for" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "slug" ]
      )
      authorize_as Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_UPDATE

      def self.perform_with_principal(workspace:, principal:, args:)
        agent = workspace.agents.find_by!(slug: args[:slug].to_s)
        token = AgentPayloads.mint(workspace, principal, agent)

        respond(AgentPayloads.summary(agent.reload).merge(token: token))
      end
    end
  end
end
