module Integrations
  # Keeps the resource map current. With no row it sweeps every enabled connection that is due, the hourly schedule, and
  # with one it sweeps that connection at once, right after it is connected or refreshed and on Sync now.
  class MapSweepJob < ApplicationJob
    queue_as :background

    def perform(environment_row = nil)
      return MapSweep.run!(environment_row) if environment_row

      IntegrationEnvironment.enabled.joins(:integration).merge(Integration.active).find_each { |row| sweep(row) }
    end

    private

    # One connection's unexpected error is recorded on it and never stops the sweep of the others.
    def sweep(row)
      MapSweep.run!(row) if MapSweep.due?(row)
    rescue StandardError => error
      Rails.logger.error({ event: "map_sweep.failed", integration_environment_id: row.id, error: error.class.name, message: error.message }.to_json)
      row.update!(map_error: MapSweep::UNEXPECTED)
    end
  end
end
