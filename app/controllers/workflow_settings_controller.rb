# How long a workspace keeps what each workflow run did, set on Settings, Workspace. After it a run keeps only its one
# line, and a pinned run keeps everything.
class WorkflowSettingsController < InertiaController
  authorizes Ability::Action::RESOURCE_WORKSPACE, update: %i[update]

  include RequiresWorkflows

  def update
    current_workspace.update!(workflow_run_retention_days: params[:workflow_run_retention_days])
    days = current_workspace.workflow_run_retention_days
    redirect_to settings_workspace_path, notice: "Workflow runs now keep their details for #{days} #{'day'.pluralize(days)}."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to settings_workspace_path, inertia: { errors: error.record.errors.to_hash }
  end
end
