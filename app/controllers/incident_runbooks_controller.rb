class IncidentRunbooksController < InertiaController
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

  private

  def runbook_name(slug)
    current_workspace.runbooks.active.find_by(slug: slug)&.name || "The runbook"
  end
end
