module Integrations
  # Every connect or refresh path goes through here, so an unreachable server
  # lands as a readable error on the row rather than an exception to catch.
  class ConnectionRefresh
    def self.run!(integration)
      DiscoveryService.sync!(integration)
      environments(integration).each { |row| HealthCheckService.check!(row) }
      true
    rescue Integrations::Error => e
      environments(integration).each { |row| row.record_health!(false, error: e.message) }
      false
    end

    def self.environments(integration)
      integration.integration_environments.enabled
    end
  end
end
