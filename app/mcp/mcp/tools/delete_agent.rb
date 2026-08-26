module Mcp
  module Tools
    class DeleteAgent < Base
      tool_name DELETE_AGENT
      description "Delete an agent by slug. Its tokens stop working immediately and its abilities " \
                  "are revoked, while everything it did stays on the timelines it touched. " \
                  "Disabling it with upsert_agent is the reversible move. Authorizes as " \
                  "permissions, which is admin-only. Docs: #{Docs::PERMISSIONS}"
      annotations(**DESTRUCTIVE)
      input_schema(
        properties: {
          slug: { type: "string", description: "Slug of the agent to delete" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "slug" ]
      )
      authorize_as Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_DELETE

      def self.perform(workspace:, args:)
        workspace.agents.find_by!(slug: args[:slug].to_s).destroy!

        respond(slug: args[:slug].to_s, deleted: true)
      end
    end
  end
end
