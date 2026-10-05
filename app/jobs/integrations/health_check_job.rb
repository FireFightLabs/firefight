module Integrations
  # Checks one connection's environment row now, for a change that should not wait for the half hourly sweep.
  class HealthCheckJob < ApplicationJob
    queue_as :default

    def perform(environment_row)
      HealthCheckService.check!(environment_row)
    end
  end
end
