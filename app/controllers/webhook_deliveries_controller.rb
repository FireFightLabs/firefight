class WebhookDeliveriesController < InertiaController
  # Replaying sends the customer's endpoint another live request, so it is
  # admin work for the same reason configuring the webhook is.
  before_action :require_admin!

  def replay
    webhook = current_workspace.webhooks.find(params[:webhook_id])
    delivery = webhook.webhook_deliveries.find(params[:id])
    delivery.replay!
    redirect_to settings_webhooks_path, notice: "Delivery replay queued"
  end
end
