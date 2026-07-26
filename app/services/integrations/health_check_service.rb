module Integrations
  class HealthCheckService
    def self.check!(environment_row)
      client = McpClient.new(server_url: environment_row.integration.server_url,
                             headers: Credentials.headers_for(environment_row))
      healthy = client.ping
      environment_row.record_health!(healthy)
      healthy
    rescue McpClient::Error
      environment_row.record_health!(false)
      false
    end
  end
end
