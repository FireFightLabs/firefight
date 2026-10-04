module Integrations
  module BaselineReaders
    # Reads what normal looks like for each Upstash Redis database on the map, from redis_get_stats over the 7d period
    # Upstash's own server offers. Upstash's docs do not give the tool's parameters, so Firefight asks for a week only
    # when the connected tool reports a period that takes 7d and a database parameter it knows. Otherwise it reads
    # nothing, rather than pass off a shorter window as a week.
    class Upstash < RemoteReader
      WEEK = "7d".freeze

      def baselines(resources, window)
        return unless on?(Capabilities::Upstash::GET_STATS)

        properties = parameters(Capabilities::Upstash::GET_STATS)
        database = Capabilities::Upstash::DATABASE.find { |name| properties.key?(name) }
        return [] unless database && Array(properties.dig(Capabilities::Upstash::PERIOD, "enum")).include?(WEEK)

        resources.select { |resource| resource.kind == ResourceMap::KIND_DATABASE }.flat_map do |resource|
          result = call(Capabilities::Upstash::GET_STATS, { database => resource.external_id, Capabilities::Upstash::PERIOD => WEEK })
          stats = readable(result, resource)
          stats ? Capabilities::Upstash::METRICS_READ.filter_map { |name, metric| baseline(resource, name, metric, stats, window) } : []
        end
      end

      private

      def readable(result, resource)
        return if result.nil?

        if result["isError"]
          Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{Capabilities::Answers.text(result).truncate(200)}")
          return
        end

        data = Capabilities::Answers.data(result)
        fields = Capabilities::Upstash::METRICS_READ.values.map(&:field)
        [ data, *(data.values if data.is_a?(Hash)) ].find { |each| each.is_a?(Hash) && fields.any? { |field| each.key?(field) } }
      end

      def baseline(resource, name, metric, stats, window)
        points = Array(stats[metric.field]).filter_map do |point|
          at = point.is_a?(Hash) && Telemetry.parse_time(point["x"])
          [ at, point["y"].to_f * metric.scale ] if at && !point["y"].nil? && window.cover?(at)
        end
        ResourceMap::Baseline::Found.new(key: resource.key, metric: name, label: metric.title, unit: metric.unit, points: points) if points.any?
      end
    end
  end
end
