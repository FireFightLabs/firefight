class Webhooks::DeactivationNotifier
  def self.notify(webhook, reason:)
    new(webhook, reason: reason).notify
  end

  def initialize(webhook, reason:)
    @webhook = webhook
    @reason  = reason
  end

  def notify
    Rails.logger.warn({
      event:          "webhooks.auto_deactivated",
      webhook_id:     @webhook.id,
      webhook_name:   @webhook.name,
      webhook_url:    @webhook.url,
      workspace_id:   @webhook.workspace_id,
      reason:         @reason,
      deactivated_at: Time.current.iso8601
    })
    post_channel_notice
  end

  private

  def post_channel_notice
    workspace = @webhook.workspace
    return if workspace.incidents_channel_id.blank?

    WorkspaceAdapter.for(workspace).post_message(
      channel_id: workspace.incidents_channel_id,
      text: ":warning: Firefight turned off the webhook #{@webhook.name} after repeated delivery failures to #{@webhook.url}. " \
            "Re-enable it from the Webhooks settings page once the endpoint is healthy.",
      blocks: nil
    )
  rescue AdapterError => e
    Rails.logger.warn({
      event:      "webhooks.deactivation_notice_failed",
      webhook_id: @webhook.id,
      error:      e.message
    })
  end
end
