module Operator
  # Sends a failed webhook delivery again, as a new delivery with the same payload bytes.
  class WebhookDeliveriesController < BaseController
    def redeliver
      delivery = WebhookDelivery.includes(:webhook).find(params[:id])
      blocked = Actions.redelivery_blocked_reason(delivery)
      return redirect_back(fallback_location: operator_incidents_path, alert: blocked) if blocked

      delivery.replay!
      redirect_back fallback_location: operator_incidents_path, notice: "Sending #{delivery.event_type} to #{delivery.webhook.name} again."
    end
  end
end
