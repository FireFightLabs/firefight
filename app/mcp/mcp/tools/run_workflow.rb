module Mcp
  module Tools
    # Runs a published workflow by its name, as its own identity, the same way Run on its page does.
    class RunWorkflow < Base
      tool_name RUN_WORKFLOW
      authorize_as Ability::Action::RESOURCE_WORKFLOWS, Ability::Action::ACTION_CREATE
      behind_flag FeatureFlags::WORKFLOWS
      description "Run a published workflow by its name, slug or another name it goes by, with a value for each input it asks " \
                  "(list_workflows names them). It runs as the workflow's own identity. Answers the run's page. Docs: #{Docs::MCP_SERVER}"
      annotations(**WRITE)
      input_schema(
        properties: {
          workflow: { type: "string", description: "The workflow's name, slug or another name it goes by" },
          inputs: { type: "object", description: "A value for each input by its key (optional for one with a default)" }
        },
        required: [ "workflow" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        workflow = Workflow.named(workspace.workflows, args[:workflow])
        return Mcp::ToolDispatcher.error_response("No workflow is called #{args[:workflow]}. list_workflows names them.") unless workflow

        run = WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON,
                                                      started_by: (principal if principal.is_a?(WorkspaceMembership)), inputs: args[:inputs].to_h)
        respond(run_id: run.id, status: run.status, page: Workflow::Links.run(run))
      rescue Workflow::Run::Refused => refused
        Mcp::ToolDispatcher.error_response(refused.message)
      end
    end
  end
end
