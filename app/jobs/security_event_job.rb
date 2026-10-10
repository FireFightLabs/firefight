# Hands one security event a provider reported to the workspace's security module, off the webhook's request.
class SecurityEventJob < ApplicationJob
  queue_as :events

  discard_on ActiveRecord::RecordNotFound

  def perform(workspace_id, event)
    workspace = Workspace.find(workspace_id)
    Investigation::SecurityTrigger.new(workspace).receive!(Integrations::SecurityEvents::Event.new(**event.symbolize_keys))
  end
end
