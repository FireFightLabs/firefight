module Mcp
  module Tools
    class GiveShoutout < Base
      tool_name GIVE_SHOUTOUT
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Thank someone for their work on an incident, posted in the incident channel, " \
                  "the same as a person running /ff shoutout. If the call requires approval, " \
                  "retry the identical call with approval_id once approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          member: { type: "string", description: "Email or platform user id of the person being thanked" },
          message: { type: "string", description: "What they did, in your own words" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "member", "message" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        incident = IncidentWrite.find!(workspace, args[:incident])
        recipient = ActionItemWrite.member_for(workspace, args[:member])

        ShoutoutService.new(workspace).give(
          incident: incident, from: principal, to: recipient, message: args[:message].to_s
        )

        respond(incident: incident.identifier, to: recipient.actor_display_name, given: true)
      end
    end
  end
end
