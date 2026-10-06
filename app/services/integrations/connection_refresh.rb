module Integrations
  # Every connect or refresh path goes through here, so an unreachable server
  # lands as a readable error on the row rather than an exception to catch.
  class ConnectionRefresh
    def self.run!(integration)
      DiscoveryService.sync!(integration)
      environments(integration).each do |row|
        HealthCheckService.check!(row)
        MapEvents.prepare!(row)
        MapSweepJob.perform_later(row)
      end
      true
    rescue Integrations::Error => e
      environments(integration).each { |row| row.record_health!(false, error: e.message) }
      false
    end

    # A provider whose health check reads through its own tools learns from them, so switching one on or off checks the
    # connection again, and what it learned is there without waiting for the next sweep.
    def self.tools_changed(integration)
      return unless integration.executor.checks_through_tools?(integration)

      environments(integration).each { |row| HealthCheckJob.perform_later(row) }
    rescue Integrations::Error
      nil
    end

    def self.environments(integration)
      integration.integration_environments.enabled
    end
  end
end
