class WebhookDeliveriesController < InertiaController
  # Replaying sends the customer's endpoint another live request, so it is
  # the same authority as configuring the webhook.
  authorizes Ability::Action::RESOURCE_WEBHOOKS, update: :replay

  def replay
    webhook = current_workspace.webhooks.find(params[:webhook_id])
    delivery = webhook.webhook_deliveries.find(params[:id])
    delivery.replay!
    redirect_to developer_webhooks_path, notice: "Delivery replay queued"
  end
end
