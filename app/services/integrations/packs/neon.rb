module Integrations
  module Packs
    # What Firefight does for a Neon connection that Neon's MCP server cannot: restoring a branch to a moment of its own
    # history (restoreProjectBranch) and reading a project's consumption over time (getConsumptionHistoryPerProjectV2),
    # both through the Neon API with the connection's own organization API key. Neon's server signs a person in with
    # tokens of its own (its authorization server is mcp.neon.tech), which the API does not take, so a connection signed
    # in that way is told to connect again with a key. Every field is the API's own (api-docs.neon.tech). Every call is
    # NeonApi's. Each answer links to the branch's or the project's console page through SourceLinks::Neon, as a server
    # call's does, from the ids it was given.
    class Neon < NativePack
      PROJECT = "project_id".freeze
      BRANCH = "branch_id".freeze
      SOURCE = "source_branch_id".freeze
      TIMESTAMP = "source_timestamp".freeze
      LSN = "source_lsn".freeze
      PRESERVE = "preserve_under_name".freeze
      ID = /\A[a-z0-9-]{1,60}\z/
      # A Postgres LSN, such as 0/1A2B3C4.
      LSN_SHAPE = %r{\A\h{1,8}/\h{1,8}\z}
      # A moment with Z or an offset, since one without a zone would be read in the server's own.
      ZONED = /(Z|[+-]\d{2}:?\d{2})\z/i
      # The consumption metrics the API returns (ConsumptionHistoryQueryMetrics), each with the unit it counts in.
      METRICS = {
        "compute_unit_seconds" => "CU-seconds", "public_network_transfer_bytes" => "bytes", "private_network_transfer_bytes" => "bytes",
        "root_branch_bytes_month" => "byte-months", "child_branch_bytes_month" => "byte-months", "instant_restore_bytes_month" => "byte-months",
        "snapshot_storage_bytes_month" => "byte-months", "extra_branches_month" => "branch-months"
      }.freeze
      DEFAULT_METRICS = %w[compute_unit_seconds public_network_transfer_bytes].freeze
      # Hourly, daily and monthly figures reach back this far (the API's granularity), so the finest that covers a range is used.
      GRANULARITIES = { "hourly" => 168.hours, "daily" => 60.days, "monthly" => 1.year }.freeze
      DEFAULT_MINUTES = 24 * 60
      NEEDS_KEY = "Neon refused this connection for its API. A connection signed in through Neon's MCP server reaches only that " \
                  "server, so connect Neon again with an organization API key, from your organization's Settings, API keys, in the token " \
                  "form, and check the key reaches this project.".freeze
      PLANS = "Neon keeps consumption history only for the Launch, Scale, Agent, Business and Enterprise plans, from when the account " \
              "moved to one.".freeze

      def self.beside_server? = true

      tool :restore_branch,
           summary: "Restores a Neon branch to how it was at a moment, keeping its current state as a branch.",
           description: "Restore a Neon branch to its own state at a past moment, or to another branch's, through the Neon API. Give " \
                        "source_timestamp (ISO 8601 with a zone) or source_lsn, and preserve_under_name, the branch its current state " \
                        "is kept as, which Neon requires when a branch is restored from itself or has children. Its computes move onto " \
                        "the restored data, so open connections drop and reconnect. Needs a connection made with an organization API key",
           params_schema: {
             "type" => "object",
             "properties" => {
               PROJECT => { "type" => "string", "description" => "The project's id" },
               BRANCH => { "type" => "string", "description" => "The branch to restore, by its id (br-...)" },
               SOURCE => { "type" => "string", "description" => "The branch whose history to restore from, by its id (optional, the branch itself)" },
               TIMESTAMP => { "type" => "string", "description" => "The moment to restore to, ISO 8601 with Z or an offset, within the project's history window" },
               LSN => { "type" => "string", "description" => "A Postgres LSN to restore to instead of a moment, such as 0/1A2B3C4" },
               PRESERVE => { "type" => "string", "description" => "The name the branch's current state is kept under" }
             },
             "required" => [ PROJECT, BRANCH ]
           },
           read_only: false

      tool :consumption_history,
           summary: "Shows a Neon project's compute time, data transfer and storage over time.",
           description: "A Neon project's consumption over a range, from the Neon API, one chart per metric: compute_unit_seconds " \
                        "(compute time), public_network_transfer_bytes and private_network_transfer_bytes (data sent out), and the " \
                        "storage metrics in byte-months. Hourly for up to 7 days, daily up to 60, monthly up to a year. Needs a " \
                        "connection made with an organization API key and a plan that keeps consumption history",
           params_schema: {
             "type" => "object",
             "properties" => {
               PROJECT => { "type" => "string", "description" => "The project's id" },
               "metrics" => { "type" => "array", "items" => { "type" => "string", "enum" => METRICS.keys },
                              "description" => "Which metrics (optional, compute_unit_seconds and public_network_transfer_bytes)" },
               "minutes" => { "type" => "integer", "description" => "How far back from now, in minutes (optional, a day)" },
               "start" => { "type" => "string", "description" => "Start of the range as an ISO 8601 time, instead of minutes (optional)" },
               "end" => { "type" => "string", "description" => "End of the range as an ISO 8601 time (optional, now)" }
             },
             "required" => [ PROJECT ]
           },
           read_only: true

      def restore_branch(environment_row:, arguments:)
        project, branch = ids(arguments, PROJECT, BRANCH)
        source = arguments[SOURCE].to_s.strip.presence || branch
        fail! "#{SOURCE} is a branch id such as br-cool-darkness-12345678." unless source.match?(ID)

        body = { SOURCE => source }.merge(point(arguments, source == branch))
        preserve = arguments[PRESERVE].to_s.strip
        fail! "Say #{PRESERVE}, the name the branch's current state is kept under. Neon requires it to restore a branch from itself." if preserve.empty? && source == branch
        body[PRESERVE] = preserve if preserve.present?

        api = api(environment_row)
        named = read { api.branch(project, branch) }["name"] || branch
        read { api.restore_branch(project, branch, body) }
        to = body[TIMESTAMP] || "LSN #{body[LSN]}"
        from = source == branch ? "its own state at #{to}" : "branch #{source} at #{to}"
        kept = preserve.present? ? " Its state before is kept as branch #{preserve}, and its child branches moved onto that one." : ""
        Telemetry.result("Neon restored #{named} to #{from}.#{kept} Its computes moved onto the restored data, so open connections " \
                         "dropped and the app reconnects.", link: nil)
      end

      def consumption_history(environment_row:, arguments:)
        project = ids(arguments, PROJECT).first
        metrics = Array(arguments["metrics"]).map(&:to_s).uniq.presence || DEFAULT_METRICS
        unknown = metrics - METRICS.keys
        fail! "Neon keeps no #{unknown.join(', ')} consumption. It keeps #{METRICS.keys.join(', ')}." if unknown.any?

        started, ended = Telemetry.range(arguments, default_minutes: DEFAULT_MINUTES, max_minutes: 365 * 24 * 60)
        granularity = GRANULARITIES.find { |_name, reach| Time.current - started <= reach }&.first || "monthly"
        api = api(environment_row)
        org = read { api.project(project) }["org_id"].presence
        fail! "Neon did not say which organization project #{project} is in, and its consumption is read by organization." unless org

        found = read(consumption: true) do
          api.consumption(org_id: org, project_id: project, from: started.utc.iso8601, to: ended.utc.iso8601, granularity: granularity, metrics: metrics)
        end
        charts = metrics.map { |metric| chart(metric, found, started, ended) }
        text = "Consumption of project #{project} on Neon, #{granularity}. Storage metrics count in byte-months and accrue over time " \
               "rather than show what is stored at a moment.\n#{Telemetry.charts_text(charts)}"
        Telemetry.result(text, link: nil, charts: charts)
      end

      private

      def ids(arguments, *names)
        names.map do |name|
          value = arguments[name].to_s.strip
          fail! "#{name} is a Neon id, such as #{name == PROJECT ? 'shiny-wind-12345678' : 'br-cool-darkness-12345678'}." unless value.match?(ID)

          value
        end
      end

      # A moment or an LSN to restore to, one of them, and one is needed to restore a branch from itself.
      def point(arguments, own)
        at = arguments[TIMESTAMP].to_s.strip
        lsn = arguments[LSN].to_s.strip
        fail! "Give #{TIMESTAMP} or #{LSN}, not both." if at.present? && lsn.present?
        fail! "Give #{TIMESTAMP} or #{LSN}, since a branch restored from itself needs a point in its history." if own && at.empty? && lsn.empty?
        return { LSN => lsn } if lsn.present? && lsn.match?(LSN_SHAPE)
        fail! "#{LSN} is a Postgres LSN such as 0/1A2B3C4." if lsn.present?
        return {} if at.empty?

        moment = moment(at)
        fail! "#{TIMESTAMP} is an ISO 8601 time with Z or an offset, such as 2026-10-20T14:30:00Z." unless moment
        fail! "#{TIMESTAMP} has to be a moment that has passed." if moment > Time.current

        { TIMESTAMP => moment.utc.iso8601 }
      end

      def moment(text)
        Time.iso8601(text) if text.match?(ZONED)
      rescue ArgumentError
        nil
      end

      def chart(metric, found, started, ended)
        points = Array(found["periods"]).flat_map { |period| Array(period["consumption"]) }.filter_map do |frame|
          at = Telemetry.parse_time(frame["timeframe_start"])
          value = Array(frame["metrics"]).find { |each| each["metric_name"] == metric }&.dig("value")
          [ at, value.to_f ] if at && value
        end.sort_by(&:first)
        Telemetry::Chart.new(title: metric.tr("_", " "), unit: METRICS.fetch(metric), series: [ Telemetry::Series.new(label: "project", points: points) ],
                             from: started, to: ended)
      end

      def api(environment_row)
        # A sign-in's token is Neon's server's own, which the API never takes, so it is refused before anything is sent.
        fail! NEEDS_KEY if Credentials.signed_in?(environment_row)

        authorization = Credentials.headers_for(environment_row)["Authorization"].to_s
        fail! NEEDS_KEY if authorization.blank?

        NeonApi.new(authorization)
      end

      def read(consumption: false)
        yield
      rescue NeonApi::Refused => error
        fail! "#{error.message}. #{NEEDS_KEY}#{" #{PLANS}" if consumption}"
      rescue NeonApi::Error => error
        fail! error.message
      end
    end
  end
end
