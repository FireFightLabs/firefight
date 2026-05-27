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
    # TODO: send admin email / in-app notification once we have a workspace-admin notifier
  end
end
