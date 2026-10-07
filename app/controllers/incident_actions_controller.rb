class IncidentActionsController < InertiaController
  authorizes Ability::Action::RESOURCE_INCIDENTS, update: %i[create pick_up assign complete create_issue rename reopen unassign]

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
  rescue Incident::NotActive => e
    redirect_to incident_path(incident), alert: e.message
  end

  # Taking and handing over are different events, which is why there are two buttons.
  # The service owns the difference.
  def pick_up
    act(:claimable?, :pick_up_action, picked_up_by: current_member)
  end

  def assign
    assignee = current_workspace.workspace_memberships.find(params.require(:member_id))
    act(:completable?, :reassign_action, assignee: assignee, reassigned_by: current_member)
  end

  def complete
    act(:completable?, :complete_action, completed_by: current_member)
  end

  def rename
    edit("The item was renamed.") { |action| service.rename_action(action: action, description: params.require(:description), renamed_by: current_member) }
  end

  def reopen
    edit("The item was reopened.") { |action| service.reopen_action(action: action, reopened_by: current_member) }
  end

  def unassign
    edit("Nobody holds the item now.") { |action| service.unassign_action(action: action, unassigned_by: current_member) }
  end

  # Opens the item's issue in the workspace's tracker, or tries again after it failed. The issue arrives in a job, and
  # the item says it is being opened until its link is there.
  def create_issue
    incident = current_workspace.incidents.find(params[:incident_id])
    action = incident.incident_actions.active.find(params[:id])

    refusal = IssueSyncService.new(current_workspace).request(action, by: current_member)
    return redirect_to(incident_path(incident), alert: refusal) if refusal

    redirect_to incident_path(incident), notice: "Opening the item's issue."
  end

  private

  # The service answers why it refused, which is the alert, and the notice says it was done.
  def edit(notice)
    incident = current_workspace.incidents.find(params[:incident_id])
    action = incident.incident_actions.active.find(params[:id])

    refusal = yield action
    redirect_to incident_path(incident), refusal ? { alert: refusal } : { notice: notice }
  end

  def service = IncidentActionService.new(current_workspace)

  def act(guard, operation, **arguments)
    incident = current_workspace.incidents.find(params[:incident_id])
    action = incident.incident_actions.active.find(params[:id])

    return redirect_to(incident_path(incident)) unless action.public_send(guard)

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

  # The picker offers members by membership id and everyone else by platform id, so both must resolve.
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
