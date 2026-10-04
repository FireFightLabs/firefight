module Integrations
  module BaselineReaders
    # What normal looks like for each service on the map that New Relic watches, by its APM name. Throughput, error rate
    # and response time are read an hour at a time over the week from Transaction events (New Relic's attribute
    # dictionary gives transactionType, error, and duration in seconds), in one NRQL query a service through
    # execute_nrql_query. A service New Relic recorded nothing for in the week has no baselines from it.
    class Newrelic < RemoteReader
      ADAPTER = Capabilities::Newrelic
      METRICS = {
        "throughput" => [ "filter(count(*), WHERE transactionType = 'Web') / 60", "Throughput", "per minute" ],
        "error_rate" => [ "percentage(count(*), WHERE error IS TRUE)", "Error rate", "%" ],
        "response_time" => [ "average(duration) * 1000", "Response time", "ms" ]
      }.freeze
      # Throughput is a reading every hour, an hour without traffic included. A rate or an average of nothing is not.
      RATIOS = %w[error_rate response_time].freeze
      SEEN = ADAPTER::SEEN

      def baselines(resources, window)
        account = settings.field(ADAPTER::ACCOUNT_SETTING)
        raise Integrations::Error, ADAPTER::NO_ACCOUNT if account.blank?
        return unless on?(ADAPTER::NRQL_TOOL)

        # A tool whose parameters Firefight does not know stops the whole read, and the connection says why.
        properties = parameters(ADAPTER::NRQL_TOOL)
        ADAPTER.nrql_arguments(properties, account, "")
        resources.select { |resource| ADAPTER::WATCHED.include?(resource.kind) }.flat_map { |resource| read(resource, properties, account, window) }
      rescue Capabilities::Unroutable => error
        raise Integrations::Error, error.message
      end

      private

      def read(resource, properties, account, window)
        selected = [ "count(*) AS '#{SEEN}'", *METRICS.map { |metric, (aggregate, _, _)| "#{aggregate} AS '#{metric}'" } ]
        query = "SELECT #{selected.join(', ')} FROM Transaction WHERE appName = #{ADAPTER.nrql_string(resource.name)} " \
                "SINCE '#{window.begin.utc.iso8601}' UNTIL '#{window.end.utc.iso8601}' TIMESERIES 1 hour"
        result = call(ADAPTER::NRQL_TOOL, ADAPTER.nrql_arguments(properties, account, query), "what normal looks like for #{resource.name}")
        if result.nil? || result["isError"]
          Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{Capabilities::Answers.text(result.to_h).truncate(200)}")
          return []
        end

        rows = ADAPTER.rows(result)&.select { |row| row["beginTimeSeconds"].is_a?(Numeric) }
        raise Integrations::Error, "New Relic answered an NRQL query without the results list Firefight reads." if rows.nil?
        return [] if rows.sum { |row| row[SEEN].to_f }.zero?

        METRICS.map do |metric, (_, label, unit)|
          counted = RATIOS.include?(metric) ? rows.select { |row| row[SEEN].to_f.positive? } : rows
          points = counted.filter_map { |row| [ Time.zone.at(row["beginTimeSeconds"]), row[metric].to_f ] unless row[metric].nil? }
          ResourceMap::Baseline::Found.new(key: resource.key, metric: metric, label: label, unit: unit, points: points)
        end
      rescue Capabilities::Unroutable => error
        Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{error.message}")
        []
      end
    end
  end
end
