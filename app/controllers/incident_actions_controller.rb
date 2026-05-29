class IncidentActionsController < InertiaController
  before_action :require_authentication

  def create
    incident = current_workspace.incidents.find(params[:incident_id])
    member = current_workspace.workspace_memberships.find_by!(user: current_user)
    assignee = resolve_assignee

    begin
      IncidentActionService.new(current_workspace).create_action(
        incident: incident,
        created_by: member,
        action_type: params.require(:action_type),
        description: params.require(:description),
        assignee: assignee
      )
    rescue AdapterError => e
      Rails.logger.error("incident_actions#create: Slack post failed — #{e.message}")
    end

    redirect_to incident_path(incident)
  end

  private

  def resolve_assignee
    return nil if params[:assignee_id].blank?

    current_workspace.workspace_memberships.find_by(platform_user_id: params[:assignee_id])
  end
end
