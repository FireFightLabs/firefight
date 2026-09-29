module Integrations
  # Keeps the resource map current. With no row it sweeps every enabled connection, the hourly schedule, and with one it
  # sweeps that connection, right after it is connected or refreshed.
  class MapSweepJob < ApplicationJob
    queue_as :background

    def perform(environment_row = nil)
      return MapSweep.run!(environment_row) if environment_row

      IntegrationEnvironment.enabled.joins(:integration).merge(Integration.active).find_each do |row|
        MapSweep.run!(row)
      end
    end
  end
end
