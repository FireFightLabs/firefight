module Integrations
  # Drops the map's change events once they are a week old. Each is kept only so a second delivery is a no-op.
  class MapEventCleanupJob < ApplicationJob
    queue_as :background

    def perform
      ResourceMap::ReceivedEvent.expired.in_batches.delete_all
    end
  end
end
