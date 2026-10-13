module Mcp
  module Tools
    class UpsertRunbook < Base
      tool_name UPSERT_RUNBOOK
      description "Create or update an incident response runbook. Pass slug to update an " \
                  "existing runbook (steps/conditions replace the current set when given); an unknown slug is an error, not a create; " \
                  "omit it to create one (name required). Attach conditions auto-attach the " \
                  "runbook to matching incidents. A step may name a tool Halon runs it with (tool and arguments), " \
                  "which makes it a runbook Halon can run by its name or an alias (run_runbook). Where the workspace has workflows, " \
                  "every step stays on the runbook as its checklist, and the steps that name a tool, the inputs and the watch are " \
                  "written into the workflow it links, made for it when it links none: published when you may publish it, otherwise " \
                  "a draft the admins are asked to publish. A change step there also needs its undo. If the call requires approval, " \
                  "retry the identical call with approval_id once approved. Docs: #{Docs::RUNBOOKS}"
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
                         "runs also names its tool, as Halon calls it, and the arguments, whose values may hold an input as {{key}}, and " \
                         "where the workspace has workflows a step that changes something says how a person puts it back as undo, e.g. " \
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
            description: "What Halon watches once every step went through, as start_watch takes it: title, steps (each with capability and " \
                         "resource, or any read tool Halon can make in a chat as tool with its arguments and an optional focus, what " \
                         "counts as done or failed, label, optional and named after what it reads when left out, and waits_for, the " \
                         "earlier steps it waits for by label or number) and minutes (optional). Inputs fill in as {{key}}"
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

      def self.perform_with_principal(workspace:, principal:, args:)
        upsert = Runbook::Upsert.new(workspace)
        target = upsert_target(workspace, args)
        by = (principal if principal.is_a?(WorkspaceMembership))
        runbook = if FeatureFlags.enabled?(workspace, FeatureFlags::WORKFLOWS) && upsert.runnable?(args)
          AbilityGateway.authorize!(principal: principal, action_key: Workflow::CREATE_KEY, workspace: workspace,
                                    params: { "runbook" => args[:name].presence || target&.name }, context: { source: AbilityGateway::SOURCE_MCP }) do
            upsert.call(target, args, by: by)
          end
        else
          upsert.call(target, args, by: by)
        end
        said = publish_or_ask(principal, upsert.workflow_written)

        respond({
          slug: runbook.slug, name: runbook.name, summary: runbook.summary,
          steps_count: runbook.runbook_steps.count, conditions_count: runbook.incident_conditions.count, runnable: runbook.runnable_now?,
          workflow: runbook.workflow_for_agents&.slice(:name, :slug, :state, :page)&.merge(said: said)&.compact
        }.compact)
      rescue Runbook::LinkedWorkflow::Refused => refused
        Mcp::ToolDispatcher.error_response(refused.message)
      end

      def self.publish_or_ask(principal, workflow)
        draft = workflow&.draft
        return unless draft

        service = WorkflowPublishService.new(workflow)
        unpublishable = service.unpublishable_words(draft)
        return unpublishable if unpublishable
        return service.ask_or_leave!(draft, by: principal).words unless service.may_publish?(draft, by: principal)

        service.publish_through_gateway!(draft, principal: principal, source: AbilityGateway::SOURCE_MCP).words
      end
      private_class_method :publish_or_ask
    end
  end
end
