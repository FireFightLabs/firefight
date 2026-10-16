# A model says its incident's page changed (Incident::LiveSignal) and never names who tells the page, so the delivery
# listens here. Resolved on each event, so a reloaded class in development is the one called.
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe(Incident::LiveSignal::EVENT) do |event|
    Incident::LiveDelivery.changed(**event.payload.slice(:incident_id, :part))
  end
end
