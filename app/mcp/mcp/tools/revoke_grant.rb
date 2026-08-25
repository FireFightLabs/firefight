module Mcp
  module Tools
    class RevokeGrant < Base
      tool_name REVOKE_GRANT
      description "Revoke a grant by its id, from list_principals. Takes effect immediately. " \
                  "Docs: #{Docs::PERMISSIONS}"
      annotations(**DESTRUCTIVE)
      authorize_as Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_DELETE
      input_schema(
        properties: {
          grant_id: { type: "string", description: "Id of the grant to revoke" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "grant_id" ]
      )

      def self.perform(workspace:, args:)
        workspace.ability_grants.find(args[:grant_id].to_s).destroy!
        respond(grant_id: args[:grant_id], revoked: true)
      end
    end
  end
end
