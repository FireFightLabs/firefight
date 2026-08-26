# Taking part in an incident from the dashboard rather than moving it: asking
# a named person to respond, bringing people into the channel, and thanking
# someone. The same services Slack and the API call, so the timeline cannot
# tell where the action came from.
class IncidentParticipationController < InertiaController
  authorizes Ability::Action::RESOURCE_INCIDENTS, update: %i[escalate invite shoutout]

  before_action :set_incident

  def escalate
    return redirect_blocked(@incident.escalation_blocked_reason) if @incident.escalation_blocked_reason

    target = member(params.require(:member_id))
    IncidentLifecycleService.new(current_workspace).escalate(
      @incident, escalated_to: target, reason: params.require(:reason), changed_by: current_member
    )

    redirect_to incident_path(@incident),
      notice: "#{target.display_name} was asked to pick up #{@incident.identifier}."
  end

  def invite
    return redirect_blocked(@incident.invite_blocked_reason) if @incident.invite_blocked_reason

    members = Array(params.require(:member_ids)).map { |reference| member(reference) }
    result = IncidentInviteService.new(current_workspace).invite!(incident: @incident, people: members)

    redirect_to incident_path(@incident), notice: invite_notice(result, members)
  end

  def shoutout
    return redirect_blocked(@incident.shoutout_blocked_reason) if @incident.shoutout_blocked_reason

    recipient = member(params.require(:member_id))
    ShoutoutService.new(current_workspace).give(
      incident: @incident, from: current_member, to: recipient, message: params.require(:message)
    )

    redirect_to incident_path(@incident), notice: "Your shoutout to #{recipient.display_name} was posted."
  end

  private

  # Counting rather than naming, because the picker only offers people this
  # workspace already has and the reader just watched themselves pick them.
  def invite_notice(result, members)
    invited = result.invited_user_ids.size
    return "Everyone you picked is already in the channel." if invited.zero? && result.failed_invites.empty?

    notice = "Invited #{invited} of #{members.size} to the channel."
    return notice if result.failed_invites.empty?

    "#{notice} #{result.failed_invites.size} could not be invited."
  end

  def redirect_blocked(reason)
    redirect_to incident_path(@incident), alert: reason
  end

  def member(reference)
    current_workspace.workspace_memberships.find(reference)
  end

  def current_member
    current_workspace.workspace_memberships.find_by!(user: current_user)
  end

  def set_incident
    @incident = current_workspace.incidents.where(deleted_at: nil).find(params[:incident_id])
  end
end
