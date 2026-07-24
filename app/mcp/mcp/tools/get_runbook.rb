module Mcp
  module Tools
    class GetRunbook < Base
      tool_name GET_RUNBOOK
      description "Fetch one incident response runbook in full by slug: its summary, full " \
                  "content, external link, and ordered steps with instructions. " \
                  "Docs: #{Docs::RUNBOOKS}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          slug: { type: "string", description: "Runbook slug" }
        },
        required: [ "slug" ]
      )

      def self.perform(workspace:, args:)
        runbook = workspace.runbooks.active.includes(:runbook_steps).find_by!(slug: args[:slug].to_s)

        respond(
          {
            slug: runbook.slug,
            name: runbook.name,
            summary: runbook.summary,
            content: runbook.content,
            external_url: runbook.external_url,
            steps: runbook.runbook_steps.map do |step|
              { position: step.position, title: step.title, instruction: step.instruction }
            end
          }.compact
        )
      end
    end
  end
end
