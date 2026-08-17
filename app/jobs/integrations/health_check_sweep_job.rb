module Integrations
  # Probes every enabled connection on a cadence so a dead credential is
  # discovered on a quiet afternoon, not mid-incident by a failing agent
  # call. Transitions to failing are logged; surfacing them to admins in
  # Slack is a pending product decision.
  class HealthCheckSweepJob < ApplicationJob
    queue_as :default

    def perform
      IntegrationEnvironment.enabled.joins(:integration)
                            .merge(Integration.active).find_each do |environment_row|
        previously_healthy = environment_row.health_status == IntegrationEnvironment::HEALTH_HEALTHY
        HealthCheckService.check!(environment_row)

        if previously_healthy && environment_row.health_status == IntegrationEnvironment::HEALTH_FAILING
          Rails.logger.warn(
            "[Integrations] #{environment_row.integration.slug} flipped to failing: #{environment_row.health_error}"
          )
        end
      end
    end
  end
end
