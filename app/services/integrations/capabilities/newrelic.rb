module Integrations
  module Capabilities
    # New Relic watches what other connections run. It answers logs, metrics, traces, errors and deploys for a service on
    # the map by the name its agent reports (appName, entity.name or service.name), and the errors of a site by its
    # browser app's name. Every answer is one NRQL query
    # Firefight writes and runs through execute_nrql_query, a tool New Relic's MCP tool reference lists
    # (docs.newrelic.com/docs/agentic-ai/mcp/tool-reference). New Relic publishes the tool's parameters only from a
    # connected server, so the query and the account go in the parameters that server reports. New Relic's nl2-nrql skill
    # (newrelic/nr-skills-hub) says the tool needs an account_id, which each environment gives at connect. Event types and
    # attributes come from New Relic's attribute dictionary, clauses from its NRQL reference
    # (docs/nrql/nrql-syntax-clauses-functions).
    module Newrelic
      extend Adapter

      PROVIDER_KEY = "newrelic".freeze
      NAME = "New Relic".freeze
      WATCHED = Adapter::APP_KINDS
      SUPPORTS = {}.freeze
      OBSERVES = { LOGS => WATCHED, METRICS => WATCHED, DEPLOYS => WATCHED, ERRORS => Adapter::ERROR_KINDS, TRACES => WATCHED }.freeze
      NRQL_TOOL = "execute_nrql_query".freeze
      TOOLS = OBSERVES.keys.index_with { NRQL_TOOL }.freeze
      # execute_nrql_query reads anything in the account, far beyond the map, so it stays offered as it is.
      WRAPPED = [].freeze
      # The connect field holding the account each environment reads (the registry's connect_fields).
      ACCOUNT_SETTING = "account_id".freeze
      NO_ACCOUNT = "Firefight does not know which New Relic account to read. An admin can connect New Relic again in Integrations, " \
                   "with the same name and environment, and give its account id.".freeze

      # The names the tool may give its arguments, in the order they are tried.
      QUERY = %w[query nrql_query nrql].freeze
      ACCOUNT = %w[account_id accountId].freeze

      # The metrics New Relic records the same way for every APM service, from Transaction events. Requests are web
      # transactions (transactionType Web) and errors are transactions with error true, both counted per minute. The
      # rest depend on how a team instruments its hosts, so the platform answers them.
      METRIC_MAP = {
        "requests" => "filter(count(*), WHERE transactionType = 'Web')",
        "errors" => "filter(count(*), WHERE error IS TRUE)"
      }.freeze
      DEFAULT_METRICS = METRIC_MAP.keys.freeze
      METRIC_TITLES = { "requests" => "Requests", "errors" => "Errors" }.freeze
      PER_MINUTE = "per minute".freeze
      # Every Transaction in the range, so a service New Relic has never seen is told apart from one with no traffic.
      SEEN = "transactions".freeze
      # A chart keeps to about this many points, and NRQL allows at most 366 buckets in a TIMESERIES.
      CHART_POINTS = 120

      LOG_LIMIT = 100
      LOG_LIMIT_MAX = Telemetry::LOG_LINE_LIMIT
      LIST_LIMIT = 20
      LIST_LIMIT_MAX = 100
      DEPLOY_DAYS = 30

      # Its baselines keep web transactions per minute as throughput, the same reading as requests. Errors are kept as
      # a share of transactions, which a count per minute does not compare with.
      def self.baseline_metric(name, _kind) = { "requests" => "throughput" }[name]

      # A regular expression goes to NRQL's RLIKE, and the stream must be what the app printed, since New Relic holds
      # what an agent sends it. A metric must be one New Relic records the same way everywhere. Without an account
      # nothing can be asked, so the platform answers.
      def self.accepts?(key, given, settings: nil)
        return false if settings&.field(ACCOUNT_SETTING).blank?
        return Array(given["metrics"]).any? && (Array(given["metrics"]).map(&:to_s) - METRIC_MAP.keys).empty? if key == METRICS
        return given["stream"].in?([ nil, "", STREAM_APP ]) if key == LOGS

        true
      end

      def self.route(key, resource, given, tool:, settings: nil)
        account = settings&.field(ACCOUNT_SETTING)
        raise Unroutable, NO_ACCOUNT if account.blank?
        if key == LOGS && !given["stream"].in?([ nil, "", STREAM_APP ])
          raise Unroutable, "New Relic holds what an app sends it, so stream must be #{STREAM_APP}. Ask the platform that runs #{resource.name} for the rest."
        end

        name = nrql_string(resource.name)
        query, present =
          case key
          when LOGS then logs(name, given)
          when METRICS then metrics(resource, name, given)
          when DEPLOYS then deploys(name, given)
          when ERRORS then resource.kind == ResourceMap::KIND_SITE ? browser_errors(name, given) : errors(name, given)
          when TRACES then traces(name, given)
          end
        Route.new(tool_name: NRQL_TOOL, arguments: nrql_arguments(tool && (Answers.properties(tool) || {}), account, query), present: present)
      end

      # The NRQL as the tool takes it, given the parameters the connected tool reports (nil when only a refusal is
      # wanted), with the account as a number unless the tool says string. A tool whose query parameter has another name
      # is refused rather than guessed at.
      def self.nrql_arguments(properties, account, query)
        return { QUERY.first => query } unless properties

        query_name = QUERY.find { |each| properties.key?(each) }
        raise Unroutable, "New Relic's #{NRQL_TOOL} takes its query in a way Firefight does not know yet, so ask it with New Relic's own tool." unless query_name

        arguments = { query_name => query }
        if (account_name = ACCOUNT.find { |each| properties.key?(each) })
          arguments[account_name] = properties.dig(account_name, "type") == "string" ? account.to_s : Integer(account.to_s, exception: false) || account.to_s
        end
        arguments
      end

      # Newest first, matched against the line itself. An APM agent's logs carry entity.name and an OpenTelemetry
      # service's carry service.name (docs/logs/logs-context).
      def self.logs(name, given)
        filters = [ "(entity.name = #{name} OR service.name = #{name})" ]
        filters << "message LIKE #{nrql_string("%#{given['text']}%")}" if given["text"].present?
        filters << "message NOT LIKE #{nrql_string("%#{given['exclude']}%")}" if given["exclude"].present?
        filters << "message RLIKE #{pattern(given['regex'])}" if given["regex"].present?
        limit = Answers.limit(given, LOG_LIMIT_MAX, default: LOG_LIMIT)
        [ "SELECT timestamp, level, log.level, message, hostname, trace.id, entity.guid FROM Log WHERE #{filters.join(' AND ')} " \
          "#{since(given)} ORDER BY timestamp DESC LIMIT #{limit}", nil ]
      end

      # Each metric per minute over buckets of a whole number of minutes, read back into charts.
      def self.metrics(resource, name, given)
        asked = Array(given["metrics"]).map(&:to_s).uniq.presence || DEFAULT_METRICS
        metric_names({ "metrics" => asked }, METRIC_MAP, NAME)
        started, ended = Answers.range(given)
        bucket = bucket_minutes(started, ended)
        selected = [ "count(*) AS '#{SEEN}'", *asked.map { |metric| "#{METRIC_MAP.fetch(metric)} / #{bucket} AS '#{metric}'" } ]
        query = "SELECT #{selected.join(', ')} FROM Transaction WHERE appName = #{name} #{since(given)} TIMESERIES #{bucket} minutes"
        [ query, ->(result) { charts_result(result, resource, asked, started, ended) } ]
      end

      # Deployment events and the newer change tracking events share these attributes, merged in one FROM (NRQL
      # reference, FROM clause). deepLink points back at whatever recorded the change.
      def self.deploys(name, given)
        limit = Answers.limit(given, LIST_LIMIT_MAX, default: LIST_LIMIT)
        [ "SELECT timestamp, version, commit, description, changelog, user, deploymentType, category, type, deepLink, entity.guid " \
          "FROM Deployment, ChangeTrackingEvent WHERE entity.name = #{name} SINCE #{DEPLOY_DAYS} days ago ORDER BY timestamp DESC LIMIT #{limit}", nil ]
      end

      # Grouped by kind, the most frequent first, with when each was first and last seen.
      def self.errors(name, given)
        filters = [ "appName = #{name}" ]
        filters << "error.message LIKE #{nrql_string("%#{given['text']}%")}" if given["text"].present?
        limit = Answers.limit(given, LIST_LIMIT_MAX, default: LIST_LIMIT)
        [ "SELECT count(*) AS 'occurrences', min(timestamp) AS 'first seen', max(timestamp) AS 'last seen', " \
          "latest(transactionName) AS 'transaction', latest(trace.id) AS 'trace id' FROM TransactionError " \
          "WHERE #{filters.join(' AND ')} FACET error.class, error.message #{since(given)} LIMIT #{limit}", nil ]
      end

      # A site's errors are what browser monitoring caught in its pages, JavaScriptError events by the browser app's name,
      # grouped by kind with the page each was last seen on (attribute dictionary, JavaScriptError).
      def self.browser_errors(name, given)
        filters = [ "appName = #{name}" ]
        filters << "errorMessage LIKE #{nrql_string("%#{given['text']}%")}" if given["text"].present?
        limit = Answers.limit(given, LIST_LIMIT_MAX, default: LIST_LIMIT)
        [ "SELECT count(*) AS 'occurrences', min(timestamp) AS 'first seen', max(timestamp) AS 'last seen', " \
          "latest(pageUrl) AS 'page', latest(stackTrace) AS 'stack trace' FROM JavaScriptError " \
          "WHERE #{filters.join(' AND ')} FACET errorClass, errorMessage #{since(given)} LIMIT #{limit}", nil ]
      end

      # The slowest transactions first, with the time spent in the database, in calls to other services and queued,
      # each in seconds, and the trace id get_distributed_trace_details reads.
      def self.traces(name, given)
        filters = [ "appName = #{name}" ]
        filters << "name LIKE #{nrql_string("%#{given['text']}%")}" if given["text"].present?
        limit = Answers.limit(given, LIST_LIMIT_MAX, default: LIST_LIMIT)
        [ "SELECT timestamp, name, duration, databaseDuration, externalDuration, queueDuration, error, http.statusCode, trace.id " \
          "FROM Transaction WHERE #{filters.join(' AND ')} #{since(given)} ORDER BY duration DESC LIMIT #{limit}", nil ]
      end

      # Minutes alone are sent as NRQL's relative time (60 minutes ago), so the same request reads the same each time and
      # an approved call matches its retry. A start or end is sent in ISO 8601, which SINCE and UNTIL take as written.
      def self.since(given)
        minutes = Answers.minutes(given)
        return "SINCE #{minutes} minutes ago" if minutes

        started, ended = Answers.range(given)
        "SINCE '#{started.utc.iso8601}' UNTIL '#{ended.utc.iso8601}'"
      end

      def self.bucket_minutes(started, ended) = [ ((ended - started) / 60.0 / CHART_POINTS).ceil, 1 ].max

      # NRQL strings sit in single quotes and the reference documents no escape inside them, so a quote or a backslash is
      # refused rather than risked.
      def self.nrql_string(text)
        text = text.to_s
        raise Unroutable, "New Relic cannot be asked for text with a quote or a backslash in it. Leave them out." if text.match?(/['\\]/)

        "'#{text}'"
      end

      # RLIKE matches the whole value in RE2 syntax, so the expression is wrapped to match anywhere in a line, across
      # its lines.
      def self.pattern(regex)
        regex = regex.to_s
        raise Unroutable, "New Relic cannot be asked for a regular expression with a quote in it. Leave it out." if regex.include?("'")

        "r'(?s).*(?:#{regex}).*'"
      end

      # The result rows of an NRQL query, as NerdGraph returns them (docs/apis/nerdgraph/examples/nerdgraph-nrql-tutorial,
      # and use-charts/chart-types for a TIMESERIES). That is a results list of rows keyed by each selected name, a
      # TIMESERIES row also holding beginTimeSeconds and endTimeSeconds. nil when the answer holds no such list.
      def self.rows(result) = find_rows(Answers.data(result.to_h))

      def self.find_rows(value)
        case value
        when Hash
          list = value["results"]
          return list if list.is_a?(Array) && list.all?(Hash)

          value.values.lazy.filter_map { |each| find_rows(each) }.first
        when Array then value.lazy.filter_map { |each| find_rows(each) }.first
        end
      end

      # One chart a metric, in the order asked, once New Relic has seen the service in the range. An answer with no
      # rows it can read is left as it came, and one with no transactions at all says so with no chart, which the
      # platform answers instead when it can.
      def self.charts_result(result, resource, asked, started, ended)
        Answers.read(result, NAME) do |body|
          series_rows = find_rows(body)&.select { |row| row["beginTimeSeconds"].is_a?(Numeric) }
          next if series_rows.blank?

          if series_rows.sum { |row| row[SEEN].to_f }.zero?
            text = "New Relic recorded no transactions for #{resource.name} from #{started.utc.iso8601} to #{ended.utc.iso8601}. " \
                   "It knows a service by the name its agent reports, so this can mean another name, or no agent there."
            next Answers.presented(result, text).merge(Telemetry::STRUCTURED => { Telemetry::CHARTS => [] })
          end

          charts = asked.map do |metric|
            points = series_rows.filter_map { |row| [ Time.zone.at(row["beginTimeSeconds"]), row[metric].to_f ] unless row[metric].nil? }
            Telemetry::Chart.new(title: "#{METRIC_TITLES.fetch(metric)} of #{resource.name}", unit: PER_MINUTE,
                                 series: [ Telemetry::Series.new(label: resource.name, points: points) ], from: started, to: ended)
          end
          Answers.presented(result, Telemetry.charts_text(charts), charts: charts)
        end
      end
      private_class_method :logs, :metrics, :deploys, :errors, :browser_errors, :traces, :since, :bucket_minutes, :pattern, :find_rows, :charts_result
    end
  end
end
