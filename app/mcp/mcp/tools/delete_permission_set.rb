module Mcp
  module Tools
    class DeletePermissionSet < Base
      tool_name DELETE_PERMISSION_SET
      description "Delete a permission set by slug. Everyone holding it loses it at once. Built-in packs cannot be deleted. " \
                  "Docs: #{Docs::PERMISSIONS}"
      annotations(**DESTRUCTIVE)
      authorize_as Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_DELETE
      input_schema(
        properties: {
          slug: { type: "string", description: "Slug of the set to delete" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "slug" ]
      )

      def self.perform(workspace:, args:)
        workspace.ability_roles.find_by!(slug: args[:slug].to_s).destroy_by_hand!
        respond(slug: args[:slug], deleted: true)
      end
    end
  end
end
