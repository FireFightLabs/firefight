module Integrations
  module BaselineReaders
    # Reads what normal looks like for each ClickHouse Cloud service on the map. One run_select_query per service reads
    # a week of metric_log hour by hour, and the replicas are added up as Northflank's containers are. The metrics and
    # units are the ones the metrics capability reads, so a live reading compares with them.
    class Clickhouse < RemoteReader
      METRICS = %w[requests errors cpu memory].freeze
      HOUR = 60

      def baselines(resources, window)
        return unless on?(Capabilities::Clickhouse::QUERY)

        from = Capabilities::Clickhouse.time_literal(window.begin)
        to = Capabilities::Clickhouse.time_literal(window.end)
        resources.select { |resource| resource.kind == ResourceMap::KIND_DATABASE }.flat_map do |resource|
          sql = Capabilities::Clickhouse.metrics_sql(METRICS, HOUR, from, to)
          result = call(Capabilities::Clickhouse::QUERY, { Capabilities::Clickhouse::SERVICE => resource.external_id, Capabilities::Clickhouse::SQL => sql })
          rows = readable(result, resource)
          rows ? METRICS.map { |name| baseline(resource, name, rows) } : []
        end
      end

      private

      def readable(result, resource)
        return if result.nil?

        if result["isError"]
          Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{Capabilities::Answers.text(result).truncate(200)}")
          return
        end

        Capabilities::Clickhouse.rows_of(Capabilities::Answers.data(result))
      end

      def baseline(resource, name, rows)
        metric = Capabilities::Clickhouse::METRICS_READ.fetch(name)
        points = rows.group_by { |row| Telemetry.parse_time(row["at"]) }.except(nil).sort.map do |at, replicas|
          [ at, replicas.sum { |row| metric.convert.call(row[name].to_f, HOUR) } ]
        end
        ResourceMap::Baseline::Found.new(key: resource.key, metric: name, label: metric.title, unit: metric.unit, points: points)
      end
    end
  end
end
