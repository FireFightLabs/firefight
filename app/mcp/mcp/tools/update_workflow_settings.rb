module Mcp
  module Tools
    # How long the workspace's workflow runs keep their details, the setting under Settings, Workspace.
    class UpdateWorkflowSettings < Base
      tool_name FirefightTools::UPDATE_WORKFLOW_SETTINGS
      authorize_as Ability::Action::RESOURCE_WORKSPACE, Ability::Action::ACTION_UPDATE
      description "Set how many days a workflow run keeps what each step did, between #{Workflow::Run::Retention::DAYS.min} and " \
                  "#{Workflow::Run::Retention::DAYS.max}. After it a run keeps only its one line, and a pinned run keeps everything. " \
                  "Only a workspace admin may call this. Docs: #{Docs::MCP_SERVER}"
      annotations(**WRITE)
      input_schema(
        properties: {
          workflow_run_retention_days: { type: "integer", minimum: Workflow::Run::Retention::DAYS.min, maximum: Workflow::Run::Retention::DAYS.max,
                                         description: "Days a run keeps its details" }
        },
        required: [ "workflow_run_retention_days" ]
      )

      def self.perform(workspace:, args:)
        workspace.update!(workflow_run_retention_days: args[:workflow_run_retention_days])
        respond(workflow_run_retention_days: workspace.workflow_run_retention_days)
      end
    end
  end
end
