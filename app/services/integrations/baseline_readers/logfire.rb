module Integrations
  module BaselineReaders
    # What normal looks like for the services Logfire watches, from a week of requests, 4xx and 5xx responses and cpu, from the
    # same SQL the capability reads (Capabilities::Logfire), in hourly buckets, through query_run. A few services go in
    # one query, so a large map is a few calls, each recorded under the map sweep, and only when the admin switched
    # query_run on.
    class Logfire < RemoteReader
      PROVIDER = Capabilities::Logfire::PROVIDER_KEY
      QUERY_RUN = Capabilities::Logfire::QUERY_RUN
      METRICS = Capabilities::Logfire::METRICS_SQL.keys.freeze
      STEP = 1.hour.to_i
      PER_QUERY = 5

      # ResourceMap::Baseline::Found readings, or nil when query_run is switched off. A batch Logfire refuses keeps
      # yesterday's baselines, and when every batch is refused Logfire's words are raised, so the connection says why.
      def baselines(resources, window)
        watched = Capabilities::Logfire::OBSERVES.fetch(Capabilities::METRICS)
        by_name = resources.select { |resource| watched.include?(resource.kind) }.group_by(&:name)
        return [] if by_name.empty?

        failures = []
        batches = by_name.keys.each_slice(PER_QUERY).to_a
        readings = []
        batches.each do |names|
          batch = read(names, window, by_name, failures)
          return nil if batch.nil?

          readings.concat(batch)
        end
        raise Integrations::Error, Sentence.join("Logfire could not read normal", failures.first) if failures.size == batches.size

        readings
      end

      private

      def read(names, window, by_name, failures)
        sql = "#{Capabilities::Logfire.metrics_sql(METRICS, names, STEP)} ORDER BY bucket"
        arguments = { "query" => sql, "min_timestamp" => window.begin.utc.iso8601, "max_timestamp" => window.end.utc.iso8601 }
        result = call(QUERY_RUN, arguments, "normal for #{names.size} services")
        return if result.nil?

        if result["isError"]
          failures << Capabilities::Answers.text(result).strip.truncate(200)
          Rails.logger.warn({ event: "baseline_sweep.batch_failed", provider: PROVIDER, error: failures.last }.to_json)
          return []
        end

        body = Capabilities::Answers.data(result)
        rows = body ? Capabilities::Logfire.rows(body) : []
        found(rows, by_name)
      end

      def found(rows, by_name)
        rows.group_by { |row| [ row["service_name"], row["metric"] ] }.flat_map do |(service, metric), each|
          next [] unless METRICS.include?(metric) && by_name[service]

          points = each.filter_map do |row|
            at = Capabilities::Answers.time_of(row["bucket"])
            value = Float(row["value"], exception: false)
            [ at, value ] if at && value&.finite?
          end
          by_name[service].map do |resource|
            ResourceMap::Baseline::Found.new(key: resource.key, metric: metric, label: Capabilities::Logfire::METRIC_TITLES.fetch(metric), unit: Capabilities::Logfire::METRIC_UNITS.fetch(metric), points: points)
          end
        end
      end
    end
  end
end
