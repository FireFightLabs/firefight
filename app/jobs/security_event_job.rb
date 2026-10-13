# Hands one security event a provider reported to the workspace's security module, off the webhook's request, and tells
# the workspace's workflows about it, whether or not the security module looks into it.
class SecurityEventJob < ApplicationJob
  queue_as :events

  discard_on ActiveRecord::RecordNotFound

  def perform(workspace_id, event)
    workspace = Workspace.find(workspace_id)
    reported = Integrations::SecurityEvents::Event.new(**event.symbolize_keys)
    Workflow::Trigger::Events.fire!(workspace, Workflow::Trigger::KIND_SECURITY_EVENT, key: "#{reported.provider}:#{reported.kind}:#{reported.reference}",
                                                                                       subject: workspace, details: reported.to_h)
    Investigation::SecurityTrigger.new(workspace).receive!(reported)
  end
end
