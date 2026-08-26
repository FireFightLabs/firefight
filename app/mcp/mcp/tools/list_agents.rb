module Mcp
  module Tools
    class ListAgents < Base
      tool_name LIST_AGENTS
      description "Every agent in this workspace, with how many live tokens and granted abilities " \
                  "each holds, and the prefix of each token so one can be revoked by name. An " \
                  "agent with no live token cannot act, and one with no abilities can authenticate " \
                  "and do nothing. Authorizes as permissions, which is admin-only. " \
                  "Docs: #{Docs::PERMISSIONS}"
      annotations(**READ_ONLY)
      input_schema(properties: {}, required: [])
      authorize_as Ability::Action::RESOURCE_PERMISSIONS

      def self.perform(workspace:, args:)
        agents = workspace.agents.where(deleted_at: nil).ordered.includes(:api_keys, ability_grants: :action)

        respond(agents: agents.map { |agent| AgentPayloads.summary(agent).merge(tokens: tokens(agent)) })
      end

      def self.tokens(agent)
        agent.live_api_keys.map do |key|
          { prefix: key.token_prefix, created_at: key.created_at.utc.iso8601, last_used_at: key.last_used_at&.utc&.iso8601 }.compact
        end
      end
    end
  end
end
