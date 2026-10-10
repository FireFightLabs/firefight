module Mcp
  module Tools
    class GetRunbook < Base
      tool_name GET_RUNBOOK
      authorize_as Ability::Action::RESOURCE_RUNBOOKS
      description "Fetch one incident response runbook in full by slug: its summary, full " \
                  "content, external link, and ordered steps with instructions. A runbook Halon can run also " \
                  "has each step's tool and arguments, its inputs, its other names and what it watches after. " \
                  "Docs: #{Docs::RUNBOOKS}"
      annotations(**READ_ONLY)
      own_words
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
              { position: step.position, title: step.title, instruction: step.instruction, tool: step.tool,
                arguments: step.arguments.presence }.compact
            end,
            inputs: runbook.inputs.presence,
            aliases: runbook.aliases.presence,
            watch: runbook.watch
          }.compact
        )
      end
    end
  end
end
