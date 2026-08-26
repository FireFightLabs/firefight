module Mcp
  module Tools
    class InviteResponders < Base
      tool_name INVITE_RESPONDERS
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Pull people into the incident channel so they can see what is happening and " \
                  "join in, the same as a person running /ff invite. Inviting someone does not " \
                  "ask them for anything: use escalate_incident when you need a named person to " \
                  "respond. If the call requires approval, retry the identical call with " \
                  "approval_id once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          members: {
            type: "array",
            items: { type: "string" },
            description: "Emails or platform user ids of the people to bring in"
          },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "members" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        incident = IncidentWrite.find!(workspace, args[:incident])
        members = Array(args[:members]).map { |reference| workspace.workspace_memberships.resolve!(reference) }
        return Mcp::ToolDispatcher.error_response("Name at least one person to invite.") if members.empty?

        result = IncidentInviteService.new(workspace).invite!(incident: incident, people: members)
        by_platform_id = members.index_by(&:platform_user_id)

        respond(
          incident: incident.identifier,
          invited: names(result.invited_user_ids, by_platform_id),
          already_here: names(result.already_in_channel_user_ids, by_platform_id),
          failed: result.failed_invites.map { |failure| { member: by_platform_id[failure[:user_id]]&.actor_display_name, error: failure[:error] } }
        )
      end

      def self.names(user_ids, by_platform_id)
        user_ids.filter_map { |user_id| by_platform_id[user_id]&.actor_display_name }
      end
      private_class_method :names
    end
  end
end
