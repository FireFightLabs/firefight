module Integrations
  module Capabilities
    # Supabase answers through the tools its MCP server publishes, from supabase-community/supabase-mcp,
    # packages/mcp-server-supabase/src/tools. A project is a database on the map and each branch is a project of its own,
    # so both are asked by their project ref. Logs come from query_logs, which runs SQL over Supabase's unified log stream
    # and which the hosted server offers in place of get_logs. Firefight writes that SQL with the columns get_logs reads
    # in src/logs.ts, every value a quoted literal. Deploys are the migrations applied, and status is the project as
    # Supabase's API answers it. A connection scoped to one project by its project_ref connect field takes no project_id,
    # so project_id goes only to a tool that asks for it.
    module Supabase
      extend Adapter

      PROVIDER = MapReaders::Supabase::NAME
      PROVIDER_KEY = MapReaders::Supabase::PROVIDER
      PROJECTS = [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ].freeze
      SUPPORTS = { LOGS => PROJECTS, DEPLOYS => PROJECTS, STATUS => PROJECTS }.freeze
      TOOLS = { LOGS => "query_logs", DEPLOYS => "list_migrations", STATUS => "get_project" }.freeze
      # Supabase's tools reach every project the account sees, far beyond the map, so they stay offered as they are.
      WRAPPED = [].freeze
      PROJECT_ID = "project_id".freeze
      SCOPED_TO = "project_ref".freeze
      # The log sources a stream reads, and the columns each is read with, as the server's get_logs reads them.
      SOURCES = { STREAM_APP => "postgres_logs", "requests" => "edge_logs" }.freeze
      COLUMNS = {
        "postgres_logs" => "timestamp, event_message, log_attributes['parsed.error_severity'] as error_severity",
        "edge_logs" => "timestamp, event_message, log_attributes['request.method'] as method, log_attributes['request.path'] as path, " \
                       "log_attributes['response.status_code'] as status_code"
      }.freeze
      PAGES = { "postgres_logs" => "logs/postgres-logs", "edge_logs" => "logs/edge-logs" }.freeze
      MIGRATIONS_PAGE = "database/migrations".freeze
      LOG_LIMIT = 200
      LOG_MOST = 1_000
      # The server refuses a log window longer than a day.
      WINDOW_MINUTES = 24 * 60
      DEPLOY_LIMIT = 20
      DEPLOY_MOST = 100
      # What the server wraps every log answer in, so the rows can be read back out of it.
      UNTRUSTED = /<untrusted-data-[^>]+>\s*(?<data>.*?)\s*<\/untrusted-data-[^>]+>/m
      MIGRATION_TIME = /\A\d{14}\z/

      def self.route(key, resource, given, tool:, settings: nil)
        ref = resource.external_id
        scoped!(resource, settings)
        case key
        when LOGS then logs(resource, ref, given, tool)
        when DEPLOYS
          Route.new(tool_name: TOOLS[DEPLOYS], arguments: project(ref, tool),
                    present: ->(result) { Answers.read(result, PROVIDER) { |data| deploys_result(resource, data, given) } })
        when STATUS
          Route.new(tool_name: TOOLS[STATUS], arguments: { "id" => ref },
                    present: ->(result) { Answers.read(result, PROVIDER) { |data| status_result(resource, data) } })
        end
      end

      # A connection scoped to one project reads only that one, whatever is asked, so another project is refused.
      def self.scoped!(resource, settings)
        scoped = settings&.field(SCOPED_TO)
        return if scoped.blank? || scoped == resource.external_id

        raise Unroutable, "This Supabase connection is scoped to project #{scoped}, so it cannot read #{resource.name}. Connect Supabase for that project too."
      end

      # A page of the project under its dashboard address, which the map read.
      def self.page(resource, path) = resource.url.present? ? "#{resource.url}/#{path}" : nil

      def self.takes_project?(tool) = Answers.properties(tool).to_h.key?(PROJECT_ID)

      def self.project(ref, tool) = tool.nil? || takes_project?(tool) ? { PROJECT_ID => ref } : {}

      def self.logs(resource, ref, given, tool)
        source = SOURCES[given["stream"].presence || STREAM_APP]
        raise Unroutable, "Supabase reads a project's Postgres logs with stream app and the API requests reaching it with stream requests. Ask query_logs for its other logs." unless source

        limit = Answers.limit(given, LOG_MOST, default: LOG_LIMIT)
        started, ended = window(given)
        filters = [ "source = #{literal(source)}" ]
        filters << "positionCaseInsensitive(event_message, #{literal(given['text'])}) > 0" if given["text"].present?
        filters << "positionCaseInsensitive(event_message, #{literal(given['exclude'])}) = 0" if given["exclude"].present?
        filters << "match(event_message, #{literal(given['regex'])})" if given["regex"].present?
        sql = "select #{COLUMNS.fetch(source)} from logs where #{filters.join(' and ')} order by timestamp desc limit #{limit}"
        arguments = project(ref, tool).merge("sql" => sql, "iso_timestamp_start" => started.utc.iso8601, "iso_timestamp_end" => ended.utc.iso8601)
        Route.new(tool_name: TOOLS[LOGS], arguments: arguments,
                  present: ->(result) { Answers.read(result, PROVIDER) { |data| logs_result(resource, source, data, limit) } })
      end

      # The window Supabase reads, which it caps at a day, so a longer one is said rather than cut short unseen.
      def self.window(given)
        started, ended = Answers.range(given)
        if ended - started > WINDOW_MINUTES.minutes
          raise Unroutable, "Supabase reads at most a day of logs a call. Ask for #{WINDOW_MINUTES} minutes or fewer, or a start and end within a day."
        end

        [ started, ended ]
      end

      # A ClickHouse string literal with its backslashes and quotes escaped, so what was asked is only ever read as text.
      def self.literal(value) = "'#{value.to_s.gsub('\\') { '\\\\' }.gsub("'") { "\\'" }}'"

      def self.logs_result(resource, source, data, limit)
        wrapped = data.is_a?(Hash) ? data["result"] : data
        inner = wrapped.is_a?(String) && (match = wrapped.match(UNTRUSTED)) ? JSON.parse(match[:data]) : wrapped
        failure = inner.is_a?(Hash) ? inner["error"] : nil
        if failure.present?
          said = failure.is_a?(Hash) ? (failure["message"] || failure.to_json) : failure.to_s
          return { "isError" => true, "content" => [ { "type" => "text", "text" => "Supabase could not read the logs: #{said}" } ] }
        end

        rows = Array(inner.is_a?(Hash) ? inner["result"] : inner)
        lines = rows.filter_map do |row|
          at = Answers.time_of(row["timestamp"])
          text = [ row["error_severity"], row["method"], row["path"], row["status_code"], row["event_message"] ].compact_blank.join(" ")
          Telemetry::LogLine.new(at: at, source: resource.name, text: text) if at && text.present?
        end.sort_by(&:at).reverse
        link = Telemetry::Link.new(provider: PROVIDER, url: page(resource, PAGES.fetch(source)))
        what = source == "edge_logs" ? "API requests to" : "Postgres logs of"
        Telemetry.result(Telemetry.logs_text(lines, asked: "#{what} #{resource.name}", limit: limit), link: link)
      end

      def self.deploys_result(resource, data, given)
        migrations = Array(data.is_a?(Hash) ? data["migrations"] : data).sort_by { |migration| migration["version"].to_s }.reverse
        link = Telemetry::Link.new(provider: PROVIDER, url: page(resource, MIGRATIONS_PAGE))
        return Telemetry.result("No migrations have been applied to #{resource.name}.", link: link) if migrations.empty?

        shown = migrations.first(Answers.limit(given, DEPLOY_MOST, default: DEPLOY_LIMIT)).map do |migration|
          version = migration["version"].to_s
          at = Time.find_zone("UTC").strptime(version, "%Y%m%d%H%M%S").iso8601 if version.match?(MIGRATION_TIME)
          [ at, "migration #{version}", migration["name"].presence ].compact.join(", ")
        end
        Telemetry.result("Latest #{shown.size} of #{migrations.size} migrations applied to #{resource.name}, newest first. A migration is " \
                         "a change to its schema, named by the version it is recorded under.\n#{shown.join("\n")}", link: link)
      end

      def self.status_result(resource, data)
        return { "isError" => true, "content" => [ { "type" => "text", "text" => data.to_json } ] } unless data.is_a?(Hash)

        facts = [ ("status #{data['status']}" if data["status"]), ("region #{data['region']}" if data["region"]),
                  ("Postgres #{data.dig('database', 'version')}" if data.dig("database", "version")),
                  ("host #{data.dig('database', 'host')}" if data.dig("database", "host")), ("created #{data['created_at']}" if data["created_at"]) ]
        Telemetry.result("How #{resource.name} stands on Supabase now: #{facts.compact.join(', ')}.", link: Answers.page(resource, PROVIDER))
      end

      private_class_method :scoped!, :page, :takes_project?, :project, :logs, :window, :literal, :logs_result, :deploys_result, :status_result
    end
  end
end
