module Operator
  # Sending a failed webhook again, with the bytes that were sent the first time, as a delivery of its own.
  class WebhookDeliveriesController < BaseController
    def redeliver
      delivery = WebhookDelivery.includes(:webhook).find(params[:id])
      return redirect_back(fallback_location: operator_incidents_path, alert: "Only a failed delivery can be sent again.") unless delivery.failed?

      delivery.replay!
      redirect_back fallback_location: operator_incidents_path, notice: "Sending #{delivery.event_type} to #{delivery.webhook.name} again."
    end
  end
end
