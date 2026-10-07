module Integrations
  # Reads the change log of every connection whose provider keeps one and sends no events. Run every minute, with no row
  # it queues one read per connection that is due by its provider's own interval, so a slow provider never holds up
  # another workspace.
  class MapEventPollJob < ApplicationJob
    queue_as :background
    limits_concurrency key: ->(environment_row = nil) { environment_row&.id || "all" }, duration: 10.minutes

    def perform(environment_row = nil)
      return MapEvents.poll!(environment_row) if environment_row

      IntegrationEnvironment.reachable.includes(:integration).find_each do |row|
        self.class.perform_later(row) if row.map_events_poll_due?
      end
    end
  end
end
