module Integrations
  module BaselineReaders
    # What normal looks like for the services Grafana watches, as a week of cpu and memory per container from the same
    # cAdvisor metrics the capability reads (Capabilities::Grafana), through query_prometheus (grafana/mcp-grafana,
    # tools/prometheus.go). A service is every pod of its container added up. Twenty containers go in one query, so a
    # large map is a few calls.
    class Grafana < RemoteReader
      QUERY_PROMETHEUS = Capabilities::Grafana::TOOLS.fetch(Capabilities::METRICS)
      METRICS = {
        "cpu" => { label: "CPU, all pods", unit: Capabilities::Grafana::METRIC_UNITS.fetch("cpu") },
        "memory" => { label: "Memory, all pods", unit: Capabilities::Grafana::METRIC_UNITS.fetch("memory") }
      }.freeze
      STEP = 15.minutes.to_i
      PER_QUERY = 20
      # A Kubernetes container name is a DNS label, so nothing else can be one and the names go into a regular
      # expression without escaping.
      CONTAINER_NAME = /\A[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\z/

      # ResourceMap::Baseline::Found readings, or nil when Prometheus cannot be read here, because its datasource is not
      # known or query_prometheus is switched off. A batch Grafana refuses keeps yesterday's baselines, and when every
      # batch is refused Grafana's words are raised, so the connection says why.
      def baselines(resources, window)
        source = HealthProbes::Grafana.datasource(settings, HealthProbes::Grafana::PROMETHEUS)
        return unless source && on?(QUERY_PROMETHEUS)

        watched = Capabilities::Grafana::OBSERVES.fetch(Capabilities::METRICS)
        by_name = resources.select { |resource| watched.include?(resource.kind) && resource.name.match?(CONTAINER_NAME) }.group_by(&:name)
        return [] if by_name.empty?

        failures = []
        batches = by_name.keys.each_slice(PER_QUERY).to_a
        readings = batches.flat_map { |names| read(source, names, window, by_name, failures) }
        raise Refused, Sentence.join("Grafana could not read normal from Prometheus", failures.first) if failures.size == batches.size

        readings
      end

      private

      def read(source, names, window, by_name, failures)
        selector = "#{Capabilities::Grafana::CONTAINER_LABEL}=~#{Capabilities::Grafana.quoted(names.join('|'))}"
        expression = METRICS.keys.map do |name|
          query = format(Capabilities::Grafana::METRIC_QUERIES.fetch(name), by: Capabilities::Grafana::CONTAINER_LABEL, selector: selector, window: "#{STEP}s")
          Capabilities::Grafana.labelled(name, query)
        end.join(" or ")
        arguments = { HealthProbes::Grafana::DATASOURCE_ARG => source["uid"], "expr" => expression, "startTime" => window.begin.utc.iso8601,
                      "endTime" => window.end.utc.iso8601, "stepSeconds" => STEP, "queryType" => "range" }
        result = call(QUERY_PROMETHEUS, arguments, "normal for #{names.size} containers")
        if result.nil? || result["isError"]
          failures << Capabilities::Answers.text(result.to_h).strip.truncate(200)
          Rails.logger.warn({ event: "baseline_sweep.batch_failed", provider: Capabilities::Grafana::PROVIDER_KEY, error: failures.last }.to_json)
          return []
        end

        body = Capabilities::Answers.data(result)
        return failed(failures, "Grafana answered with something that is not JSON.") unless body.is_a?(Hash)

        found(body, by_name)
      end

      def failed(failures, said)
        failures << said
        []
      end

      def found(body, by_name)
        Array(body["data"]).flat_map do |stream|
          metric = stream.dig("metric", Capabilities::Grafana::METRIC_LABEL)
          described = METRICS[metric]
          resources = by_name[stream.dig("metric", Capabilities::Grafana::CONTAINER_LABEL)]
          next [] unless described && resources

          points = Array(stream["values"]).filter_map do |at, value|
            number = Float(value, exception: false)
            [ Time.zone.at(at.to_f).utc, number ] if at && number&.finite?
          end
          resources.map { |resource| ResourceMap::Baseline::Found.new(key: resource.key, metric: metric, label: described[:label], unit: described[:unit], points: points) }
        end
      end
    end
  end
end
