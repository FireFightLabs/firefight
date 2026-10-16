module Mcp
  module Tools
    class GetRunbook < Base
      tool_name FirefightTools::GET_RUNBOOK
      authorize_as Ability::Action::RESOURCE_RUNBOOKS
      description "Fetch one incident response runbook in full by slug: its summary, full " \
                  "content, external link, ordered steps with instructions and its other names. The steps are its checklist, and " \
                  "what it runs (each step's tool and arguments, the inputs and the watch) is the workflow it links, named under " \
                  "workflow with its page. " \
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
        parts = runbook.readable_parts

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
            inputs: parts.inputs.presence,
            aliases: runbook.aliases.presence,
            watch: parts.watch,
            workflow: runbook.workflow_for_agents
          }.compact
        )
      end
    end
  end
end
