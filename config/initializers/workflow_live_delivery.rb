# A model says its workflow's page changed (Workflow::LiveSignal) and never names who tells the page, so the delivery
# listens here. Resolved on each event, so a reloaded class in development is the one called.
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe(Workflow::LiveSignal::EVENT) do |event|
    Workflow::LiveDelivery.changed(**event.payload.slice(:workflow_id, :part))
  end
end
