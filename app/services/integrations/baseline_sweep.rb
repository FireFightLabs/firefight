module Integrations
  # Reads a week of metrics for what one connection reaches, once a day, into what normal looks like per resource. A
  # connection whose provider reads no metrics has nothing to do. One that cannot be read keeps yesterday's baselines and
  # says why on the connection, as a failed map sweep does.
  class BaselineSweep
    # Queues a read for every connection, so one slow provider never holds up another workspace.
    def self.queue_all
      IntegrationEnvironment.enabled.joins(:integration).merge(Integration.active).find_each { |row| BaselineSweepJob.perform_later(row) }
    end

    def self.run!(environment_row, now: Time.current)
      resources = ResourceMap::Resource.present.where(integration_environment: environment_row).to_a
      return 0 if resources.empty?

      window = (now - ResourceMap::Baseline::WINDOW)..now
      found = environment_row.integration.executor.baselines_of(environment_row, resources, window)
      return 0 unless found

      recorded = ResourceMap::Baseline.record!(environment_row.integration.workspace, resources, found, window_from: window.begin, window_to: window.end)
      environment_row.update!(baseline_error: nil)
      recorded
    rescue Integrations::Error => error
      environment_row.update!(baseline_error: error.message)
      0
    end
  end
end
