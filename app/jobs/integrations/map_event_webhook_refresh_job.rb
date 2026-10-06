module Integrations
  # Extends the webhooks Firefight registered for map changes before their provider lets them lapse.
  class MapEventWebhookRefreshJob < ApplicationJob
    queue_as :background

    def perform
      IntegrationEnvironment.reachable.where.not(map_events_webhook_id: nil)
                            .where(integration_environments: { map_events_expires_at: ..MapEvents::REFRESH_WITHIN.from_now })
                            .includes(:integration).find_each { |row| MapEvents.refresh!(row) }
    end
  end
end
