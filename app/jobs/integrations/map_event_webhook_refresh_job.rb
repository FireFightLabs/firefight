module Integrations
  # Extends the webhooks Firefight registered for map changes before their provider lets them lapse.
  class MapEventWebhookRefreshJob < ApplicationJob
    queue_as :background

    def perform
      IntegrationEnvironment.reachable.map_events_webhook_due(MapEvents::REFRESH_WITHIN).includes(:integration).find_each { |row| MapEvents.refresh!(row) }
    end
  end
end
