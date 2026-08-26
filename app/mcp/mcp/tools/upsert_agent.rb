module Mcp
  module Tools
    class UpsertAgent < Base
      tool_name UPSERT_AGENT
      description "Create or change an agent, which is an AI that takes part in incidents under " \
                  "its own name. Pass slug to change an existing one, or leave it out to create. " \
                  "Creating one returns its token once and never again, so hand it over " \
                  "immediately. A new agent holds no abilities at all: grant it what it needs with " \
                  "grant_ability. Authorizes as permissions, which is admin-only and cannot be " \
                  "granted to a machine, so an agent can never create another agent. " \
                  "Docs: #{Docs::PERMISSIONS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          slug: { type: "string", description: "Slug of the one to change; omit to create" },
          name: { type: "string", description: "What a timeline calls it. Required when creating" },
          description: { type: "string", description: "One sentence saying what it does" },
          enabled: { type: "boolean", description: "false stops it acting while keeping its grants" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )
      upserts Ability::Action::RESOURCE_PERMISSIONS, scope: ->(workspace) { workspace.agents }

      def self.perform_with_principal(workspace:, principal:, args:)
        agent = upsert_target(workspace, args)
        return respond(AgentPayloads.summary(update(agent, args))) if agent

        raise ArgumentError, "name is required when creating." if args[:name].blank?

        agent, token = AgentPayloads.create(workspace, principal, args)
        respond(AgentPayloads.summary(agent).merge(token: token))
      end

      def self.update(agent, args)
        agent.update!({ name: args[:name], description: args[:description], enabled: args[:enabled] }.compact)
        agent
      end
      private_class_method :update
    end
  end
end
