# Applies a change an issue tracker sent by its webhook to the items linked to that issue.
class IssueChangeJob < ApplicationJob
  queue_as :default

  def perform(workspace:, event:)
    IssueSyncService.new(workspace).apply(Integrations::Issues::Event.from_job(event))
  end
end
