module Integrations
  module Capabilities
    # Honeycomb watches what other connections run, so it answers traces, errors and request counts for a resource on
    # the map by its OpenTelemetry service.name, which is the resource's name, in the Honeycomb environment the
    # connection was set up for. Every answer is one run_query on Honeycomb's hosted MCP server. Its arguments
    # (environment_slug, dataset_slug, query_spec) are from Honeycomb's own agent skill (honeycombio/agent-skill,
    # honeycomb/hooks/scripts/validate-query.sh), the query specification and relative time_range ("60m") from its
    # query examples (skills/query-patterns/references/query-examples.md) and Honeycomb's query specification
    # reference, and __all__ for every dataset of an environment from Honeycomb's earlier server
    # (honeycombio/honeycomb-mcp, src/tools/run-query.ts). The columns (service.name, name, duration_ms, error,
    # is_root, trace.trace_id) are the ones those references query. run_query answers in markdown with a link to the
    # query in Honeycomb, which the agent reads as it is.
    module Honeycomb
      extend Adapter

      PROVIDER_KEY = "honeycomb".freeze
      NAME = "Honeycomb".freeze
      WATCHED = Adapter::APP_KINDS
      SUPPORTS = {}.freeze
      OBSERVES = { METRICS => WATCHED, TRACES => WATCHED, ERRORS => Adapter::ERROR_KINDS }.freeze
      RUN_QUERY = "run_query".freeze
      TOOLS = { METRICS => RUN_QUERY, TRACES => RUN_QUERY, ERRORS => RUN_QUERY }.freeze
      # run_query reads every dataset Honeycomb holds, far beyond the map, so it stays offered as it is.
      WRAPPED = [].freeze
      # The Honeycomb environment a connection reads, which the connect form asks for.
      ENVIRONMENT = "environment_slug".freeze
      EVERY_DATASET = "__all__".freeze
      SERVICE = "service.name".freeze
      # Requests are root spans and errors the root spans that failed. One metric a query, as the reference queries do.
      METRIC_FILTERS = {
        "requests" => [ { "column" => "is_root", "op" => "=", "value" => true } ],
        "errors" => [ { "column" => "is_root", "op" => "=", "value" => true }, { "column" => "error", "op" => "=", "value" => true } ]
      }.freeze
      TRACE_LIMIT = 50
      ERROR_LIMIT = 50

      def self.environment(settings) = settings&.field(ENVIRONMENT)

      # A connection answers only once it knows its Honeycomb environment.
      def self.reaches?(settings, _key) = environment(settings).present?

      # Errors are grouped by operation, so text to search for, or any metric but requests or errors asked alone, is
      # for another connection.
      def self.accepts?(key, given, settings: nil)
        case key
        when METRICS then Array(given["metrics"]).size == 1 && METRIC_FILTERS.key?(Array(given["metrics"]).first.to_s)
        when ERRORS then given["text"].blank?
        else true
        end
      end

      def self.route_refusal(key, resource, given, settings: nil)
        return if accepts?(key, given)
        if key == METRICS
          return "Honeycomb counts #{METRIC_FILTERS.keys.join(' or ')} one a call, from #{resource.name}'s root spans. Ask the platform that runs it for the rest."
        end

        "Honeycomb groups #{resource.name}'s failed spans by operation and does not search their text. Ask with run_query on the columns get_dataset_columns lists."
      end

      def self.route(key, resource, given, tool:, settings: nil)
        refusal = route_refusal(key, resource, given)
        raise Unroutable, refusal if refusal

        slug = environment(settings)
        raise Unroutable, "This Honeycomb connection does not say which Honeycomb environment it reads. Connect it again and name the environment." unless slug

        spec = case key
        when METRICS then metrics(resource, given)
        when TRACES then traces(resource, given)
        when ERRORS then errors(resource, given)
        end
        arguments = { ENVIRONMENT => slug, "dataset_slug" => EVERY_DATASET, "query_spec" => spec.merge(times(given)) }
        Route.new(tool_name: RUN_QUERY, arguments: Answers.known!(tool, arguments, NAME))
      end

      def self.traces(resource, given)
        filters = [ service(resource) ]
        filters << { "column" => "name", "op" => "contains", "value" => given["text"].to_s } if given["text"].present?
        { "calculations" => [ { "op" => "MAX", "column" => "duration_ms" } ], "filters" => filters, "breakdowns" => [ "trace.trace_id", "name" ],
          "orders" => [ { "op" => "MAX", "column" => "duration_ms", "order" => "descending" } ], "limit" => Answers.limit(given, TRACE_LIMIT) }
      end

      def self.errors(resource, given)
        { "calculations" => [ { "op" => "COUNT" } ], "filters" => [ service(resource), { "column" => "error", "op" => "=", "value" => true } ],
          "breakdowns" => [ "name" ], "orders" => [ { "op" => "COUNT", "order" => "descending" } ], "limit" => Answers.limit(given, ERROR_LIMIT) }
      end

      def self.metrics(resource, given)
        { "calculations" => [ { "op" => "COUNT" } ], "filters" => [ service(resource), *METRIC_FILTERS.fetch(Array(given["metrics"]).first.to_s) ] }
      end

      def self.service(resource) = { "column" => SERVICE, "op" => "=", "value" => resource.name }

      # Minutes alone are sent as Honeycomb's relative time_range (60m), so the same request reads the same each time and
      # an approved call matches its retry. A start or end is sent as start_time and end_time, in Unix seconds.
      def self.times(given)
        minutes = Answers.minutes(given)
        return { "time_range" => "#{minutes}m" } if minutes

        started, ended = Answers.range(given)
        { "start_time" => started.to_i, "end_time" => ended.to_i }
      end

      private_class_method :traces, :errors, :metrics, :service, :times
    end
  end
end
