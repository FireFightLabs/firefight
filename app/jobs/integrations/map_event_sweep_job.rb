module Integrations
  # Sweeps a connection in full because a change event named something its provider cannot read on its own. Any number
  # of them for one connection is one sweep, since one asked before the last sweep ran has nothing left to read.
  class MapEventSweepJob < ApplicationJob
    queue_as :background
    limits_concurrency key: ->(environment_row, _asked_at) { environment_row.id }, duration: 1.hour

    def perform(environment_row, asked_at)
      swept = environment_row.reload.map_swept_at
      return if swept && swept >= Time.iso8601(asked_at)

      MapSweep.run!(environment_row)
    end
  end
end
