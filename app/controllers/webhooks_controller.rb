class WebhooksController < InertiaController
  before_action :require_authentication
  before_action :require_admin!, except: [ :sample_payload ]
  before_action :set_webhook, only: [ :update, :destroy, :test, :activate, :deactivate, :signing_secret ]

  def create
    webhook = current_workspace.webhooks.new(webhook_params)

    if webhook.save
      redirect_to settings_webhooks_path, notice: "#{webhook.name} was created."
    else
      redirect_back fallback_location: settings_webhooks_path, inertia: { errors: webhook.errors.to_hash }
    end
  end

  def update
    if @webhook.update(webhook_params)
      redirect_to settings_webhooks_path, notice: "#{@webhook.name} was updated."
    else
      redirect_back fallback_location: settings_webhooks_path, inertia: { errors: @webhook.errors.to_hash }
    end
  end

  # The secret leaves the server only when an admin asks for it, so it is not
  # sitting in every page load of the settings screen waiting to be read out
  # of the props.
  def signing_secret
    render json: { signingSecret: @webhook.signing_secret }
  end

  def destroy
    @webhook.destroy!
    redirect_to settings_webhooks_path, notice: "#{@webhook.name} was deleted."
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
      redirect_to settings_webhooks_path, notice: "Test delivery queued"
    else
      redirect_to settings_webhooks_path, alert: "No matching events found to test with"
    end
  end

  def activate
    @webhook.activate!
    redirect_to settings_webhooks_path, notice: "#{@webhook.name} was activated."
  end

  def deactivate
    @webhook.deactivate!
    redirect_to settings_webhooks_path, notice: "#{@webhook.name} was deactivated."
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
end
