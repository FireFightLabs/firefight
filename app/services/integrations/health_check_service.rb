module Integrations
  class HealthCheckService
    def self.check!(environment_row)
      environment_row.integration.executor.check_health!(environment_row)
      environment_row.record_health!(true)
      learn_scope_names(environment_row)
      true
    rescue Integrations::Error => e
      environment_row.record_health!(false, error: e.message)
      false
    end

    # A connection that chooses what it reads, such as projects, lists them again so they are named by their names, and
    # one reading every one has them to offer as a tool's parameter. A listing the token may not make leaves the ids.
    def self.learn_scope_names(environment_row)
      settings = ConnectionSettings.of(environment_row)
      settings.scope_options if settings.scope_field && environment_row.integration.native?
    rescue Integrations::Error
      nil
    end
    private_class_method :learn_scope_names
  end
end
