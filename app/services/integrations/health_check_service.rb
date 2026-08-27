module Integrations
  class HealthCheckService
    def self.check!(environment_row)
      environment_row.integration.executor.check_health!(environment_row)
      environment_row.record_health!(true)
      true
    rescue Integrations::Error => e
      environment_row.record_health!(false, error: e.message)
      false
    end
  end
end
