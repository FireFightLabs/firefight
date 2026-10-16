module Mcp
  module Tools
    class ListMemberAccess < Base
      extend GatewayPayloads

      tool_name FirefightTools::LIST_MEMBER_ACCESS
      description "What members can read and change in each connected tool, as the Who can do what rows on the Permissions " \
                  "screen show it. Each row has a read and a change choice: everyone (every member, including people who " \
                  "join later), nobody, or chosen (the people listed). left_out are members kept from a read everyone has, " \
                  "and through lists members a row leaves out who still reach the tool through another permission set or " \
                  "single abilities. Admins can always do everything. Change a row with set_member_access, using its " \
                  "permission_set. Docs: #{Docs::PERMISSIONS}"
      annotations(**READ_ONLY)
      own_words
      authorize_as Ability::Action::RESOURCE_PERMISSIONS
      input_schema(properties: {}, required: [])

      def self.perform(workspace:, args:)
        overview = Ability::Role.member_access_of(workspace)
        names = overview.members.index_by(&:id)
        respond(connections: overview.connections.map { |connection| member_access_payload(connection, names) })
      end
    end
  end
end
