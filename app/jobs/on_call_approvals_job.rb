# Asks someone just escalated to about the requests waiting in the incident that they may decide as whoever is on call.
class OnCallApprovalsJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(incident_id, member_id)
    incident = Incident.find(incident_id)
    ApprovalNotificationService.ask_on_call!(incident, incident.workspace.workspace_memberships.find(member_id))
  end
end
