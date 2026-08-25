class IncidentRunbooksController < InertiaController
  authorizes Ability::Action::RESOURCE_INCIDENTS, update: %i[create claim_step]

  def create
    incident = current_workspace.incidents.find(params[:incident_id])
    member = current_workspace.workspace_memberships.find_by!(user: current_user)

    begin
      runbook = RunbookAttachmentService.new(current_workspace).attach_by_slug(
        incident: incident, slug: params.require(:slug), attached_by: member
      )
    rescue ActiveRecord::RecordNotFound
      return redirect_to incident_path(incident), alert: "That runbook is no longer available."
    rescue AdapterError => e
      Rails.logger.error("incident_runbooks#create: Slack post failed — #{e.message}")
      return redirect_to incident_path(incident), alert: "#{runbook_name(params[:slug])} was attached, but posting it to Slack failed."
    end

    redirect_to incident_path(incident), notice: "#{runbook.runbook.name} was attached."
  end

  # Claiming a step creates the action item behind it, or hands over the one
  # that already exists. The service decides which, so this never has to know
  # whether anyone has touched the step before.
  def claim_step
    incident = current_workspace.incidents.find(params[:incident_id])
    incident_runbook = incident.incident_runbooks.find(params[:incident_runbook_id])
    step = incident_runbook.runbook.runbook_steps.find(params[:step_id])
    member = current_workspace.workspace_memberships.find_by!(user: current_user)

    begin
      IncidentActionService.new(current_workspace).assign_step(
        incident: incident, runbook_step: step, assignee: member, assigned_by: member
      )
    rescue AdapterError => e
      Rails.logger.error("incident_runbooks#claim_step: Slack post failed — #{e.message}")
    end

    redirect_to incident_path(incident)
  end

  private

  def runbook_name(slug)
    current_workspace.runbooks.active.find_by(slug: slug)&.name || "The runbook"
  end
end
