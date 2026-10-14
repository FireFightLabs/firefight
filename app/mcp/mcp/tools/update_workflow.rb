module Mcp
  module Tools
    # One workflow's settings, the ones its Settings page changes (Workflow::Settings). Only what is given changes. It
    # changes a live workflow's limits, so it is marked destructive: Halon asks the person on a confirmation in the chat
    # before it runs (Chat::Tools::Firefight#destructive_by_declaration?), and the gateway and approval rules still decide.
    class UpdateWorkflow < Base
      tool_name UPDATE_WORKFLOW
      authorize_as Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_UPDATE
      behind_flag FeatureFlags::WORKFLOWS
      description "Change one workflow's settings, the ones its Settings page holds: its name and description, owning team, spending ceiling " \
                  "per run (AI and sandbox time together), most runs per hour, one live run per subject, what a change does in a freeze " \
                  "window and the all clear. Only what you give changes, and null clears the spending ceiling, the owning team or the " \
                  "subject. Docs: #{Docs::MCP_SERVER}"
      annotations(**DESTRUCTIVE)
      input_schema(
        properties: {
          workflow: { type: "string", description: "The workflow's name, slug or another name it goes by" },
          name: { type: "string", description: "What it is called" },
          description: { type: "string", description: "What it does, in a sentence" },
          owner_team_id: { type: %w[string null], description: "The id of a team on the catalog whose channel hears of a failed run, null for none" },
          cost_cap_cents: { type: %w[integer null], minimum: 1, description: "The most one run may spend on AI and sandbox time, in cents, null for no ceiling" },
          runs_per_hour: { type: "integer", minimum: Workflow::Limits::RUNS_PER_HOUR.min, maximum: Workflow::Limits::RUNS_PER_HOUR.max,
                           description: "Most runs it starts in an hour. A run its trigger would start past it is skipped and counted on its page" },
          subject_key: { type: %w[string null], description: "One live run per what this names, such as {{inputs.service}}, null to let runs overlap" },
          freeze_behaviour: { type: "string", enum: Workflow::FREEZE_BEHAVIOURS, description: "What a change does in a freeze window: wait for it to end, or stop the run" },
          all_clear: { type: "boolean", description: "Post a one line all clear when a run finds nothing" }
        },
        required: [ "workflow" ]
      )

      def self.perform(workspace:, args:)
        workflow = Workflow.named(workspace.workflows, args[:workflow])
        return Mcp::ToolDispatcher.error_response("No workflow is called #{args[:workflow]}. list_workflows names them.") unless workflow

        workflow.update_settings!(args.to_h.except(:workflow))
        respond(workflow: workflow.settings_summary, said: "#{workflow.name} was updated.")
      rescue ActiveRecord::RecordInvalid => invalid
        Mcp::ToolDispatcher.error_response(invalid.record.errors.full_messages.to_sentence)
      end
    end
  end
end
