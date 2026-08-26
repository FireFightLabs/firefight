module Mcp
  module Tools
    class UpdatePostmortem < Base
      tool_name UPDATE_POSTMORTEM
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Rewrite the body of a postmortem. Send the whole document as HTML, since this " \
                  "replaces what was there rather than appending, so read the current one with " \
                  "get_postmortem first and pass back the version it gave you. If somebody edited " \
                  "it in between, the call is refused rather than throwing their work away, and " \
                  "you read again and reapply. The markup is sanitised down to what the editor " \
                  "allows, and every version is kept, so a revision is recoverable. If the call " \
                  "requires approval, retry the identical call with approval_id once approved. " \
                  "Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          html: { type: "string", description: "The whole document. Replaces the current body" },
          version: { type: "integer", description: "The version get_postmortem returned for the body you edited" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "incident", "html", "version" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        PostmortemPayloads.with_postmortem(workspace, args[:incident]) do |postmortem|
          postmortem.update_content!(args[:html].to_s, by: principal, expected_version: args[:version])

          respond(PostmortemPayloads.summary(postmortem.reload))
        end
      end
    end
  end
end
