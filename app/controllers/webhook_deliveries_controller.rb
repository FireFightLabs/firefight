class WebhookDeliveriesController < InertiaController
  # Replaying sends the customer's endpoint another live request, so it is
  # the same authority as configuring the webhook.
  authorizes Ability::Action::RESOURCE_WEBHOOKS, read: %i[index show], update: :replay

  def index
    webhook = current_workspace.webhooks.find(params[:webhook_id])
    deliveries = webhook.webhook_deliveries.ordered.limit(10)

    render inertia: "webhooks/deliveries/index", props: {
      webhook: webhook.as_json(only: [ :id, :name ]),
      deliveries: deliveries.as_json(only: [ :id, :event_type, :state, :response_code, :error_message, :delivered_at, :created_at ])
    }
  end

  def show
    webhook = current_workspace.webhooks.find(params[:webhook_id])
    delivery = webhook.webhook_deliveries.find(params[:id])

    render inertia: "webhooks/deliveries/show", props: {
      webhook: webhook.as_json(only: [ :id, :name ]),
      delivery: delivery.as_json(only: [ :id, :event_type, :state, :request_headers, :request_body, :response_code, :error_message, :delivered_at, :created_at ])
    }
  end

  def replay
    webhook = current_workspace.webhooks.find(params[:webhook_id])
    delivery = webhook.webhook_deliveries.find(params[:id])
    delivery.replay!
    redirect_to settings_webhooks_path, notice: "Delivery replay queued"
  end
end
