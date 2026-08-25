module Mcp
  module Tools
    class UpsertPermissionSet < Base
      extend GatewayPayloads

      tool_name UPSERT_PERMISSION_SET
      description "Create or update a permission set, a named bundle of abilities granted as one. " \
                  "Pass slug to update an existing set; omit it to create one from the name. " \
                  "abilities is the set's full contents, not a delta. Docs: #{Docs::PERMISSIONS}"
      annotations(**WRITE)
      upserts Ability::Action::RESOURCE_PERMISSIONS, scope: ->(workspace) { workspace.ability_roles }
      input_schema(
        properties: {
          slug: { type: "string", description: "Slug of the set to update; omit to create" },
          name: { type: "string", description: "Display name, required when creating" },
          abilities: { type: "array", items: { type: "string" }, description: "Ability keys the set covers, from list_abilities" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )

      def self.perform(workspace:, args:)
        set = upsert_target(workspace, args) || workspace.ability_roles.create!(name: args[:name].to_s)
        set.update!(name: args[:name].to_s) if args[:name].present? && set.name != args[:name].to_s
        if args.key?(:abilities)
          set.sync_actions!(Ability::Action.grantable_for(workspace).where(key: Array(args[:abilities]).map(&:to_s)).pluck(:id))
        end

        respond(permission_set_payload(set.reload))
      end
    end
  end
end
