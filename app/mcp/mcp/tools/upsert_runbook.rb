module Mcp
  module Tools
    class UpsertRunbook < Base
      tool_name UPSERT_RUNBOOK
      description "Create or update an incident response runbook. Pass slug to update an " \
                  "existing runbook (steps/conditions replace the current set when given); an unknown slug is an error, not a create; " \
                  "omit it to create one (name required). Attach conditions auto-attach the " \
                  "runbook to matching incidents. A step may name a tool Halon runs it with (tool and arguments), " \
                  "which makes it a runbook Halon can run by its name or an alias (run_runbook). If the call requires approval, retry the " \
                  "identical call with approval_id once approved. Docs: #{Docs::RUNBOOKS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          slug: { type: "string", description: "Existing runbook slug to update; omit to create. An unknown slug is an error, not a create" },
          name: { type: "string", description: "Runbook name (required on create)" },
          summary: { type: "string", description: "One-line summary shown in search results" },
          content: { type: "string", description: "Full runbook content (markdown)" },
          external_url: { type: "string", description: "Link to an external doc, if any" },
          steps: {
            type: "array",
            description: "Ordered steps, e.g. [{\"title\": \"...\", \"instruction\": \"...\"}]; replaces existing steps. A step Halon " \
                         "runs also names its tool, as Halon calls it, and the arguments, whose values may hold an input as {{key}}, e.g. " \
                         "{\"title\": \"Start the release\", \"tool\": \"run_workflow\", \"arguments\": {\"workflow\": \"release.yml\", \"inputs\": {\"bump\": \"{{bump}}\"}}}",
            items: { type: "object" }
          },
          inputs: {
            type: "array",
            description: "What to ask the person each time it runs, e.g. [{\"key\": \"bump\", \"question\": \"Which version bump?\", \"default\": \"patch\"}]. " \
                         "A step's arguments and the watch name an input as {{key}}. Replaces existing inputs",
            items: { type: "object" }
          },
          aliases: {
            type: "array",
            description: "Other names people call it by, such as \"release firefight\". Replaces existing aliases",
            items: { type: "string" }
          },
          watch: {
            type: "object",
            description: "What Halon watches once every step went through, as start_watch takes it: title, steps (each with label, " \
                         "capability, resource and what counts as done or failed) and minutes (optional). Inputs fill in as {{key}}"
          },
          conditions: {
            type: "array",
            description: "Attach conditions, e.g. [{\"condition_field\": \"severity\", \"operator\": \"one_of\", \"values\": [\"critical\"]}]. " \
                         "A custom_field condition names its field too, e.g. [{\"condition_field\": \"custom_field\", " \
                         "\"custom_field\": \"affected_service\", \"operator\": \"one_of\", \"values\": [\"checkout\"]}]. " \
                         "Values accept ids or names: a severity or incident_type slug, an option label for a fixed list, " \
                         "a catalog entry slug for a catalog-backed field. Replaces existing conditions",
            items: { type: "object" }
          },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )

      upserts Ability::Action::RESOURCE_RUNBOOKS, scope: ->(workspace) { workspace.runbooks.active }

      def self.perform(workspace:, args:)
        runbook = Runbook::Upsert.new(workspace).call(upsert_target(workspace, args), args)

        respond(
          slug: runbook.slug, name: runbook.name, summary: runbook.summary,
          steps_count: runbook.runbook_steps.count, conditions_count: runbook.incident_conditions.count, runnable: runbook.procedure?
        )
      end
    end
  end
end
