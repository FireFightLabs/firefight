module Integrations
  class HealthCheckService
    def self.check!(environment_row)
      integration = environment_row.integration
      if integration.native?
        NativePacks.fetch!(integration).check_health!(environment_row)
      else
        McpClient.new(server_url: integration.server_url,
                      headers: Credentials.headers_for(environment_row)).ping
      end
      environment_row.record_health!(true)
      true
    rescue McpClient::Error, NativePack::Error => e
      environment_row.record_health!(false, error: e.message)
      false
    end
  end
end
