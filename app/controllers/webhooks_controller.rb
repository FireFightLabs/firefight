class WebhooksController < InertiaController
  before_action :require_authentication
  before_action :set_webhook, only: [ :show, :update, :destroy, :test, :activate, :deactivate ]

  def index
    webhooks = current_workspace.webhooks.ordered
    render inertia: "webhooks/index", props: {
      webhooks: webhooks.as_json(only: [ :id, :name, :url, :active, :subscribed_events, :created_at ])
    }
  end

  def show
    deliveries = @webhook.webhook_deliveries.ordered.limit(10)
    render inertia: "webhooks/show", props: {
      webhook: webhook_json(@webhook),
      deliveries: deliveries.as_json(only: [ :id, :event_type, :state, :response_code, :error_message, :delivered_at, :created_at ])
    }
  end

  def create
    webhook = current_workspace.webhooks.new(webhook_params)

    if webhook.save
      redirect_to webhook_path(webhook)
    else
      redirect_back fallback_location: webhooks_path, inertia: { errors: webhook.errors.to_hash }
    end
  end

  def update
    if @webhook.update(webhook_params)
      redirect_to webhook_path(@webhook)
    else
      redirect_back fallback_location: webhook_path(@webhook), inertia: { errors: @webhook.errors.to_hash }
    end
  end

  def destroy
    @webhook.destroy!
    redirect_to webhooks_path
  end

  def test
    event = current_workspace.incidents
      .joins(:incident_events)
      .order("incident_events.created_at DESC")
      .first
      &.incident_events
      &.find_by(event_type: @webhook.subscribed_events)

    if event
      WebhookDelivery.create!(
        webhook: @webhook,
        incident_event: event,
        event_type: event.event_type
      )
      redirect_to webhook_path(@webhook), notice: "Test delivery queued"
    else
      redirect_to webhook_path(@webhook), alert: "No matching events found to test with"
    end
  end

  def activate
    @webhook.activate!
    redirect_to webhook_path(@webhook)
  end

  def deactivate
    @webhook.deactivate!
    redirect_to webhook_path(@webhook)
  end

  def sample_payload
    event_type = params[:event_type]

    unless Webhook::SUBSCRIBABLE_EVENTS.include?(event_type)
      render json: { error: "Unknown event type" }, status: :unprocessable_entity
      return
    end

    template = Webhooks::PayloadRenderer.template_for(event_type)
    render json: { event_type: event_type, template: template }
  end

  private

  def set_webhook
    @webhook = current_workspace.webhooks.find(params[:id])
  end

  def webhook_params
    params.expect(webhook: [ :name, :url, subscribed_events: [] ])
  end

  def webhook_json(webhook)
    webhook.as_json(only: [ :id, :name, :url, :active, :subscribed_events, :signing_secret, :created_at, :updated_at ])
  end
end
