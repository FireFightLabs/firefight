# Takes a change made in Firefight to an item's issue in the workspace's tracker, or opens the issue, as Firefight's
# issue sync. by is whoever's change it was, which the ledger names.
class IssueSyncJob < ApplicationJob
  queue_as :default

  def perform(operation:, action:, by:, fields: [], approval_id: nil)
    workspace = action.incident.workspace
    IssueSyncService.new(workspace).perform(operation, action, by, fields: fields, approval_id: approval_id)
  end
end
