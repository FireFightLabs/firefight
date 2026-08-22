class WebhookDeliveriesController < InertiaController
  before_action :require_authentication
  # Replaying sends the customer's endpoint another live request, so it is
  # admin work for the same reason configuring the webhook is.
  before_action :require_admin!

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
