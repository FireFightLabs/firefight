# Extends the issue tracker webhooks Firefight registered before the tracker lets them expire.
class IssueWebhookRefreshJob < ApplicationJob
  queue_as :default

  # Jira lets a registered webhook lapse after 30 days, so one with a week left is extended.
  DUE_WITHIN = 7.days

  def perform
    due = IntegrationEnvironment.issue_webhook_due(DUE_WITHIN)
    Workspace.where(id: Integration.where(id: due.select(:integration_id)).select(:workspace_id)).find_each do |workspace|
      IssueSyncService.new(workspace).refresh_webhook
    end
  end
end
