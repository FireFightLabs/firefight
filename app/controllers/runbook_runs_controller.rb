# Run it on a runbook, from its page or from an incident it is attached to.
class RunbookRunsController < InertiaController
  include RequiresWorkflows

  authorizes Ability::Action::RESOURCE_WORKFLOWS, create: :create

  def create
    runbook = current_workspace.runbooks.active.find(params[:runbook_id])
    incident = current_workspace.incidents.find(params[:incident_id]) if params[:incident_id].present?
    run = RunbookRunService.new(runbook).start!(by: current_membership, inputs: inputs(runbook), incident: incident)

    flash.inertia[:links] = [ { label: "Follow its run", url: workflow_run_path(run.workflow_id, run) } ]
    redirect_back fallback_location: settings_runbooks_path, notice: "#{run.workflow.name} is running."
  rescue Workflow::Run::Refused => refused
    redirect_back fallback_location: settings_runbooks_path, alert: refused.message
  end

  private

  def inputs(runbook)
    asked = Workflow::Trigger.input_keys(runbook.workflow&.live_version&.trigger)
    params.fetch(:inputs, {}).permit(*asked).to_h
  end
end
