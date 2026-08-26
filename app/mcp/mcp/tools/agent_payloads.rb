module Mcp
  module Tools
    # What the agent tools share. Minting a credential alongside the agent is
    # one operation, since an agent without one can do nothing and leaving it
    # to a second call is a step everyone forgets.
    module AgentPayloads
      def self.create(workspace, principal, args)
        ActiveRecord::Base.transaction do
          agent = workspace.agents.create!(
            name: args[:name], slug: args[:slug].presence || args[:name].to_s.parameterize(separator: "_"),
            description: args[:description]
          )
          [ agent, mint(workspace, principal, agent) ]
        end
      end

      def self.mint(workspace, principal, agent)
        ApiKey.create_with_token!(
          workspace: workspace,
          created_by: creator_for(principal),
          agent: agent,
          name: "#{agent.name} token"
        ).last
      end

      # A token records the membership that asked for it. Only an admin's own
      # token reaches these tools, so the principal is always a person.
      def self.creator_for(principal)
        principal.is_a?(WorkspaceMembership) ? principal : principal.on_behalf_of
      end

      def self.summary(agent)
        {
          slug: agent.slug,
          name: agent.name,
          description: agent.description,
          enabled: agent.enabled?,
          live_tokens: agent.live_api_keys.size,
          granted_abilities: agent.ability_grants.size
        }.compact
      end
    end
  end
end
