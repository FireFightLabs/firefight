module Integrations
  # Re-reads what a connection offers and records whether it answered. Every
  # path that connects or refreshes goes through here, so an unreachable
  # server always lands as a readable error on the row rather than an
  # exception the caller has to remember to catch.
  class ConnectionRefresh
    def self.run!(integration)
      DiscoveryService.sync!(integration)
      environments(integration).each { |row| HealthCheckService.check!(row) }
      true
    rescue McpClient::Error => e
      environments(integration).each { |row| row.record_health!(false, error: e.message) }
      false
    end

    def self.environments(integration)
      integration.integration_environments.enabled
    end
  end
end
