module Integrations
  class HealthCheckService
    # A connection made through an app installation first reads what the provider says of it, so one removed or
    # suspended there reads as failing with why, and one that works again recovers.
    def self.check!(environment_row)
      Installations.check!(environment_row)
      Installations.stopped!(environment_row)
      environment_row.integration.executor.check_health!(environment_row)
      environment_row.record_health!(true)
      true
    rescue Integrations::Error => e
      environment_row.record_health!(false, error: e.message)
      false
    end
  end
end
