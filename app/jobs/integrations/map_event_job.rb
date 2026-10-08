module Integrations
  # Reads one scope of a connection again after its provider said something there changed. Queued a little after each
  # event, and the first to run takes every event waiting on the scope, so a burst is one re-read. Two re-reads of the
  # same scope never run at once.
  class MapEventJob < ApplicationJob
    queue_as :background
    limits_concurrency key: ->(environment_row, scope_key) { "#{environment_row.id}:#{scope_key}" }, duration: ResourceMap::ReceivedEvent::READ_LEASE

    def perform(environment_row, scope_key)
      MapEvents.reread!(environment_row, scope_key)
    end
  end
end
