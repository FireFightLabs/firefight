module Mcp
  module Tools
    class SetMemberAccess < Base
      extend GatewayPayloads

      tool_name FirefightTools::SET_MEMBER_ACCESS
      description "Set what members can read or change in one connected tool, the same as a Who can do what dropdown. " \
                  "permission_set is the row's read or change permission_set from list_member_access. choice is everyone " \
                  "(every member, including people who join later), nobody, or chosen with people. Chosen people are " \
                  "granted the set in every environment and every other member's grant of it is revoked. Changes still " \
                  "follow approval rules. Docs: #{Docs::PERMISSIONS}"
      annotations(**WRITE)
      authorize_as Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_UPDATE
      input_schema(
        properties: {
          permission_set: { type: "string", description: "The row's read or change permission_set slug, from list_member_access" },
          choice: { type: "string", enum: Ability::Role::CHOICES, description: "everyone, nobody or chosen" },
          people: { type: "array", items: { type: "string" }, description: "With chosen, the members by id from list_principals, or by email" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "permission_set", "choice" ]
      )

      # The caller is kept on any grant this makes, as grant_ability keeps it.
      def self.perform_with_principal(workspace:, principal: nil, args:)
        pack = workspace.ability_roles.find_by!(slug: args[:permission_set].to_s)
        people = Array(args[:people]).map { |reference| workspace.workspace_memberships.resolve!(reference.to_s) }
        pack.let_members!(args[:choice].to_s, people: people, by: principal)

        overview = Ability::Role.member_access_of(workspace)
        connection = overview.connections.find { |row| row.integration.id == pack.integration_id }
        respond(member_access_payload(connection, overview.members.index_by(&:id)).merge(notice: pack.member_access_notice(args[:choice].to_s, people)))
      end
    end
  end
end
