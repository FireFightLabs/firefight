module Integrations
  class HealthCheckService
    def self.check!(environment_row)
      client = McpClient.new(server_url: environment_row.integration.server_url,
                             headers: Credentials.headers_for(environment_row))
      client.ping
      environment_row.record_health!(true)
      true
    rescue McpClient::Error => e
      environment_row.record_health!(false, error: e.message)
      false
    end
  end
end
