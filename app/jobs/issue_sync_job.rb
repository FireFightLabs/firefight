# Takes a change made in Firefight to an item's issue in the workspace's tracker, or opens the issue, as whoever made it.
class IssueSyncJob < ApplicationJob
  queue_as :default

  def perform(operation:, action:, principal:, fields: [], approval_id: nil)
    workspace = action.incident.workspace
    IssueSyncService.new(workspace).perform(operation, action, principal, fields: fields, approval_id: approval_id)
  end
end
