module Mcp
  module Tools
    class GetPostmortem < Base
      tool_name GET_POSTMORTEM
      authorize_as Ability::Action::RESOURCE_INCIDENTS
      description "The postmortem written for an incident, as HTML, along with its status and who " \
                  "wrote it. An incident with no postmortem yet comes back as not found, and " \
                  "get_incident says whether one exists. Docs: #{Docs::INCIDENTS}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" }
        },
        required: [ "incident" ]
      )

      def self.perform(workspace:, args:)
        PostmortemPayloads.with_postmortem(workspace, args[:incident]) do |postmortem|
          respond(PostmortemPayloads.summary(postmortem).merge(html: postmortem.html_content))
        end
      end
    end
  end
end
