module Mcp
  module Tools
    class ListPrincipals < Base
      extend GatewayPayloads

      tool_name LIST_PRINCIPALS
      description "Everyone who can hold a grant, people, agents and service keys, with the grants " \
                  "each holds. Use the kind and id with grant_ability, and a person's id as an " \
                  "approver in upsert_approval_rule. Docs: #{Docs::PERMISSIONS}"
      annotations(**READ_ONLY)
      authorize_as Ability::Action::RESOURCE_PERMISSIONS
      input_schema(
        properties: {
          kind: { type: "string", description: "user, agent or api_key; omit for all" }
        },
        required: []
      )

      def self.perform(workspace:, args:)
        principals = Ability::Principal.all(workspace)
        principals = principals.select { |principal| principal.actor_kind == args[:kind].to_s } if args[:kind].present?

        respond(principals: principals.map do |principal|
          {
            kind: principal.actor_kind, id: principal.id, name: principal.actor_display_name,
            implicit_authority: principal.implicit_authority.to_s,
            grants: principal.ability_grants.map { |grant| grant_payload(grant) }
          }
        end)
      end
    end
  end
end
