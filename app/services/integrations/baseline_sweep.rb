module Integrations
  # Reads a week of metrics for what one connection reaches, or for what an observability tool watches on the map, once
  # a day, into what normal looks like per resource. A connection whose provider reads no metrics has nothing to do. One
  # that cannot be read keeps yesterday's baselines and says why on the connection, as a failed map sweep does.
  class BaselineSweep
    # Queues a read for every connection, so one slow provider never holds up another workspace.
    def self.queue_all
      IntegrationEnvironment.enabled.joins(:integration).merge(Integration.active).find_each { |row| BaselineSweepJob.perform_later(row) }
    end

    def self.run!(environment_row, now: Time.current)
      held = ResourceMap::Resource.present.where(integration_environment: environment_row).to_a
      watched = Capabilities.watched(environment_row, Capabilities::METRICS) - held
      resources = held + watched
      return 0 if resources.empty?

      window = (now - ResourceMap::Baseline::WINDOW)..now
      found = environment_row.integration.executor.baselines_of(environment_row, resources, window)
      return 0 unless found

      found = named(found, watched, environment_row.integration.name)
      recorded = ResourceMap::Baseline.record!(environment_row, resources, found, window_from: window.begin, window_to: window.end)
      environment_row.update!(baseline_error: nil)
      recorded
    rescue Integrations::Error => error
      environment_row.update!(baseline_error: error.message)
      0
    end

    # A reading of a resource another connection runs says which connection read it, such as "CPU (Datadog)", since the
    # one that runs it may read the same metric.
    def self.named(found, watched, name)
      keys = watched.map(&:key)
      found.map { |reading| keys.include?(reading.key) ? reading.with(label: "#{reading.label} (#{name})") : reading }
    end
    private_class_method :named
  end
end
