module Mcp
  module Tools
    class SetPostmortemStatus < Base
      tool_name SET_POSTMORTEM_STATUS
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Move a postmortem along, from draft to in progress, in review, or completed. " \
                  "Where it sits is how a team knows whether it still needs writing or reading. " \
                  "If the call requires approval, retry the identical call with approval_id once " \
                  "approved. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          status: { type: "string", enum: Postmortem::STATUSES, description: "Where it now sits" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "status" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        PostmortemPayloads.with_postmortem(workspace, args[:incident]) do |postmortem|
          postmortem.update_status!(args[:status].to_s, by: principal)

          respond(PostmortemPayloads.summary(postmortem.reload))
        end
      end
    end
  end
end
