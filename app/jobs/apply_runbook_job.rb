# Turning a runbook's steps into action items fans out one Slack message per
# step, so the "add steps as actions" button enqueues this instead of running
# inline in the interaction handler.
class ApplyRunbookJob < ApplicationJob
  queue_as :default

  def perform(workspace_id:, incident_runbook_id:, user_id:)
    workspace = Workspace.find(workspace_id)
    incident_runbook = workspace.incident_runbooks.find(incident_runbook_id)
    applied_by = workspace.workspace_memberships.find_by!(platform_user_id: user_id)

    RunbookAttachmentService.new(workspace).apply(
      incident_runbook: incident_runbook,
      applied_by: applied_by
    )
  end
end
