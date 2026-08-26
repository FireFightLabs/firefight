# Taking part in an incident rather than changing its status: pulling people
# in, asking a named person to respond, connecting it to another incident,
# thanking someone, and claiming a runbook step. Every one of these is a thing
# a person can do from Slack, reachable by whatever is holding the key.
class Api::V1::IncidentParticipationController < Api::V1::ApiController
  before_action :set_incident
  before_action :authorize_update

  def escalate
    target = current_workspace.workspace_memberships.resolve!(params.require(:member_id))
    @event = IncidentLifecycleService.new(current_workspace).escalate(
      @incident, escalated_to: target, reason: params.require(:reason), changed_by: Current.principal
    )

    render json: {
      incident_id: @incident.id,
      escalated_to: { id: target.id, name: target.actor_display_name },
      reason: @event.metadata["reason"],
      acknowledged: false
    }, status: :created
  end

  def invite
    members = Array(params.require(:member_ids)).map { |reference| current_workspace.workspace_memberships.resolve!(reference) }
    result = IncidentInviteService.new(current_workspace).invite!(incident: @incident, people: members)

    render json: {
      incident_id: @incident.id,
      invited: named(result.invited),
      already_here: named(result.already_in_channel),
      failed: result.failed.map { |failure| { member: failure.person.actor_display_name, error: failure.error } }
    }
  end

  def link
    other = current_workspace.incidents.where(deleted_at: nil).find(params.require(:other_incident_id))
    relationship = params.require(:relationship)

    service = IncidentRelationshipService.new(current_workspace)
    if relationship == IncidentRelationship::DUPLICATE
      service.mark_duplicate(source: @incident, canonical: other, created_by: Current.principal)
    else
      service.link_related(source: @incident, target: other, created_by: Current.principal)
    end

    render json: {
      incident_id: @incident.id,
      other_incident_id: other.id,
      relationship: relationship,
      status: @incident.reload.incident_status.slug
    }, status: :created
  end

  def shoutout
    recipient = current_workspace.workspace_memberships.resolve!(params.require(:member_id))
    shoutout = ShoutoutService.new(current_workspace).give(
      incident: @incident, from: Current.principal, to: recipient, message: params.require(:message)
    )

    render json: {
      id: shoutout.id,
      incident_id: @incident.id,
      to: { id: recipient.id, name: recipient.actor_display_name }
    }, status: :created
  end

  def claim_runbook_step
    attachment = @incident.incident_runbooks.find(params.require(:runbook_id))
    step = attachment.runbook.runbook_steps.find(params.require(:step_id))

    @action_item = IncidentActionService.new(current_workspace).assign_step(
      incident: @incident,
      runbook_step: step,
      assignee: params[:member_id].present? ? current_workspace.workspace_memberships.resolve!(params[:member_id]) : Current.principal,
      assigned_by: Current.principal
    )

    render "api/v1/action_items/show", status: :created
  end

  private

  def named(people)
    people.map { |person| { id: person.id, name: person.actor_display_name } }
  end

  def set_incident
    @incident = current_workspace.incidents.where(deleted_at: nil).find(params[:id])
  end

  def authorize_update
    authorize!(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE)
  end
end
