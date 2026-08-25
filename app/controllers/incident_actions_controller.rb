class IncidentActionsController < InertiaController
  authorizes Ability::Action::RESOURCE_INCIDENTS, update: %i[create pick_up assign complete]

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

  # Taking an item yourself and handing it to someone else are different
  # events, which is why Slack has two buttons and so does this. The service
  # owns the difference, including that a handover announces and taking your
  # own work does not.
  def pick_up
    act(:pick_up_action, picked_up_by: current_member) { |action| action.open? && !action.assigned? }
  end

  def assign
    assignee = current_workspace.workspace_memberships.find(params.require(:member_id))
    act(:reassign_action, assignee: assignee, reassigned_by: current_member) { |action| !action.done? }
  end

  def complete
    act(:complete_action, completed_by: current_member) { |action| !action.done? }
  end

  private

  # Every one of these is the same shape: find the item, check the model still
  # allows it, call the service, come back to the page.
  def act(operation, **arguments)
    incident = current_workspace.incidents.find(params[:incident_id])
    action = incident.incident_actions.active.find(params[:id])

    return redirect_to(incident_path(incident)) unless yield(action)

    begin
      IncidentActionService.new(current_workspace).public_send(operation, action: action, **arguments)
    rescue AdapterError => e
      Rails.logger.error("incident_actions##{operation}: Slack post failed — #{e.message}")
    end

    redirect_to incident_path(incident)
  end

  def current_member
    current_workspace.workspace_memberships.find_by!(user: current_user)
  end

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
