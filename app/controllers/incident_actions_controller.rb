class IncidentActionsController < InertiaController
  ASSIGNEE_UNAVAILABLE = "Couldn't load that user's profile from Slack. Please try again in a moment.".freeze

  def create
    incident = current_workspace.incidents.find(params[:incident_id])
    member = current_workspace.workspace_memberships.find_by!(user: current_user)

    assignee = resolve_assignee
    if params[:assignee_id].present? && assignee.nil?
      return redirect_to incident_path(incident), alert: ASSIGNEE_UNAVAILABLE
    end

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

  # The picker offers people already here under their membership id and
  # everyone else under their platform id, so both have to resolve.
  def resolve_assignee
    return nil if params[:assignee_id].blank?

    current_workspace.workspace_memberships.resolve(params[:assignee_id]) ||
      WorkspaceMemberProvisioner.find_or_provision!(
        workspace: current_workspace,
        platform_user_id: params[:assignee_id],
        adapter: current_workspace.adapter
      )
  end
end
