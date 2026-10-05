module Integrations
  module BaselineReaders
    # What normal looks like for the services SigNoz watches, from a week of requests and errors per minute, counted from
    # their spans the way the capability counts them (Capabilities::Signoz), in hourly steps, through
    # signoz_aggregate_traces grouped by service and has_error. Twenty services go in one query, so a large map is a few
    # calls, each recorded under the map sweep, and only when the admin switched the tool on.
    class Signoz < RemoteReader
      PROVIDER = Capabilities::Signoz::PROVIDER_KEY
      AGGREGATE = Capabilities::Signoz::AGGREGATE
      STEP = 1.hour.to_i
      PER_QUERY = 20
      SERVICE = "service.name".freeze
      LABELS = { "requests" => "Requests", "errors" => "Errors" }.freeze

      # ResourceMap::Baseline::Found readings, or nil when the tool is switched off. A batch SigNoz refuses keeps
      # yesterday's baselines, and when every batch is refused SigNoz's words are raised, so the connection says why.
      def baselines(resources, window)
        watched = Capabilities::Signoz::OBSERVES.fetch(Capabilities::METRICS)
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
        raise Integrations::Error, Sentence.join("SigNoz could not read normal", failures.first) if failures.size == batches.size

        readings
      end

      private

      def read(names, window, by_name, failures)
        arguments = {
          "aggregation" => "count", "groupBy" => "#{SERVICE}, #{Capabilities::Signoz::ERROR_FIELD}", "requestType" => "time_series",
          "filter" => "#{SERVICE} IN (#{names.map { |name| Capabilities::Signoz.quoted(name) }.join(', ')})", "stepInterval" => STEP,
          "start" => (window.begin.to_f * 1000).to_i, "end" => (window.end.to_f * 1000).to_i, "limit" => 10_000
        }
        result = call(AGGREGATE, arguments, "normal for #{names.size} services")
        return if result.nil?

        if result["isError"]
          failures << Capabilities::Answers.text(result).strip.truncate(200)
          Rails.logger.warn({ event: "baseline_sweep.batch_failed", provider: PROVIDER, error: failures.last }.to_json)
          return []
        end

        found(Capabilities::Answers.data(result), by_name)
      end

      def found(body, by_name)
        series = Array(body.is_a?(Hash) ? body.dig("data", "data", "results") : nil).flat_map { |each| Array(each["aggregations"]) }.flat_map { |each| Array(each["series"]) }
        series.group_by { |each| label(each, SERVICE) }.flat_map do |service, list|
          next [] unless by_name[service]

          { "requests" => list, "errors" => list.select { |each| label(each, Capabilities::Signoz::ERROR_FIELD) == "true" } }.flat_map do |metric, chosen|
            points = chosen.flat_map { |each| Array(each["values"]) }.group_by { |point| point["timestamp"] }
                           .filter_map { |at, values| [ Capabilities::Answers.time_of(at), values.sum { |value| value["value"].to_f } / (STEP / 60.0) ] if at }.sort_by(&:first)
            by_name[service].map do |resource|
              ResourceMap::Baseline::Found.new(key: resource.key, metric: metric, label: LABELS.fetch(metric), unit: "per minute", points: points)
            end
          end
        end
      end

      def label(series, name) = Array(series["labels"]).find { |each| each.dig("key", "name") == name }&.fetch("value", nil).to_s
    end
  end
end
