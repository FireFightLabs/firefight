module Integrations
  module Capabilities
    # Cloudflare answers through its execute tool. Firefight writes every request itself, each value a JSON literal, the
    # way the map's reader and the read guard do, so the agent's words never become code. Each answer is read back into
    # the shapes every capability returns. The endpoints and fields used are the ones Cloudflare's API and GraphQL
    # Analytics docs give.
    module Cloudflare
      extend Adapter

      EXECUTE = ReadGuards::Cloudflare::TOOL
      PROVIDER = "Cloudflare".freeze
      SUPPORTS = {
        LOGS => [ ResourceMap::KIND_WORKER ],
        METRICS => [ ResourceMap::KIND_WORKER, ResourceMap::KIND_ZONE ],
        DEPLOYS => [ ResourceMap::KIND_WORKER, ResourceMap::KIND_SITE ],
        STATUS => [ ResourceMap::KIND_WORKER, ResourceMap::KIND_ZONE, ResourceMap::KIND_SITE ],
        # A Worker's deployment switches versions at once, so only a Pages project's builds take a time worth reading.
        HISTORY => [ ResourceMap::KIND_SITE ],
        ROLLBACK => [ ResourceMap::KIND_WORKER, ResourceMap::KIND_SITE ]
      }.freeze
      TOOLS = SUPPORTS.keys.index_with { EXECUTE }.freeze
      # execute does far more than any one capability, so it stays offered as it is.
      WRAPPED = [].freeze
      LOG_LIMIT = 200
      DEPLOY_LIMIT = 10
      STATUS_LIMIT = 4_000
      # GraphQL Analytics answers at most this many rows, and Firefight buckets them into about this many points.
      ROWS = 10_000
      POINTS = 60
      BUCKETS = [ 1, 5, 15, 60, 360, 1440 ].freeze
      WORKER_METRICS = { "requests" => "requests", "errors" => "errors", "cpu_time" => "cpuTimeP50" }.freeze
      ZONE_METRICS = { "requests" => "all", "http_4xx" => "client", "http_5xx" => "server" }.freeze
      DEFAULTS = { ResourceMap::KIND_WORKER => %w[requests errors], ResourceMap::KIND_ZONE => %w[requests http_5xx] }.freeze
      TITLES = { "requests" => "Requests", "errors" => "Errors", "cpu_time" => "CPU time, median", "http_4xx" => "4xx responses", "http_5xx" => "5xx responses" }.freeze
      UNITS = { "cpu_time" => "ms" }.freeze

      WORKER_QUERY = <<~GRAPHQL.squish.freeze
        query ($accountTag: string, $scriptName: string, $start: string, $end: string) { viewer { accounts(filter: {accountTag: $accountTag}) {
        workersInvocationsAdaptive(limit: #{ROWS}, filter: {scriptName: $scriptName, datetime_geq: $start, datetime_leq: $end}) {
        sum { requests errors } quantiles { cpuTimeP50 } dimensions { datetime } } } } }
      GRAPHQL
      ZONE_SERIES = {
        "all" => "", "client" => ", edgeResponseStatus_geq: 400, edgeResponseStatus_lt: 500",
        "server" => ", edgeResponseStatus_geq: 500, edgeResponseStatus_lt: 600"
      }.freeze
      ZONE_QUERY = <<~GRAPHQL.squish.freeze
        query ($zoneTag: string, $start: string, $end: string) { viewer { zones(filter: {zoneTag: $zoneTag}) {
        #{ZONE_SERIES.map { |name, filter| "#{name}: httpRequestsAdaptiveGroups(limit: #{ROWS}, filter: {datetime_geq: $start, datetime_leq: $end#{filter}}) { count dimensions { datetimeHour } }" }.join(' ')}
        } } }
      GRAPHQL

      def self.route(key, resource, given, tool: nil, settings: nil)
        account = account_of(resource)
        case [ key, resource.kind ]
        in [ LOGS, _ ] then logs(resource, account, given)
        in [ METRICS, ResourceMap::KIND_WORKER ] then metrics(resource, account, given, WORKER_METRICS, WORKER_QUERY,
                                                              { "accountTag" => account, "scriptName" => resource.external_id })
        in [ METRICS, ResourceMap::KIND_ZONE ] then metrics(resource, account, given, ZONE_METRICS, ZONE_QUERY, { "zoneTag" => resource.external_id })
        in [ DEPLOYS, ResourceMap::KIND_WORKER ] then deploys(resource, account, given, "/accounts/#{account}/workers/scripts/#{resource.external_id}/deployments")
        in [ DEPLOYS, ResourceMap::KIND_SITE ] then deploys(resource, account, given, "/accounts/#{account}/pages/projects/#{resource.external_id}/deployments")
        in [ HISTORY, ResourceMap::KIND_SITE ] then history(resource, account, given, "/accounts/#{account}/pages/projects/#{resource.external_id}/deployments")
        in [ STATUS, ResourceMap::KIND_WORKER ] then status(resource, account, "/accounts/#{account}/workers/scripts/#{resource.external_id}/settings")
        in [ STATUS, ResourceMap::KIND_ZONE ] then status(resource, account, "/zones/#{resource.external_id}")
        in [ STATUS, ResourceMap::KIND_SITE ] then status(resource, account, "/accounts/#{account}/pages/projects/#{resource.external_id}")
        in [ ROLLBACK, ResourceMap::KIND_WORKER ]
          version = target(given)
          change(account, { "method" => "POST", "path" => "/accounts/#{account}/workers/scripts/#{resource.external_id}/deployments",
                            "body" => { "strategy" => "percentage", "versions" => [ { "version_id" => version, "percentage" => 100 } ],
                                        "annotations" => { "workers/message" => "Rolled back to #{version} by Firefight" } } },
                 "#{resource.name} now serves version #{version} to all traffic.")
        in [ ROLLBACK, ResourceMap::KIND_SITE ]
          deployment = target(given)
          change(account, { "method" => "POST", "path" => "/accounts/#{account}/pages/projects/#{resource.external_id}/deployments/#{deployment}/rollback" },
                 "#{resource.name} is rolled back to deployment #{deployment}.")
        end
      end

      # The account a resource is in. The map keeps the account's name, and the reader writes every page address as
      # the dashboard, then the account's id (MapReaders::Cloudflare#dashboard).
      def self.account_of(resource)
        id = URI.parse(resource.url.to_s).path.split("/")[1] if resource.url.to_s.start_with?(MapReaders::Cloudflare::DASHBOARD)
        id.presence || raise(Unroutable, "The Cloudflare account of #{resource.name} is not known, so it cannot be asked for this.")
      end

      def self.logs(resource, account, given)
        raise Unroutable, "Cloudflare keeps only what a Worker prints, so stream must be app." if given["stream"].present? && given["stream"] != "app"

        limit = given["limit"].to_i.positive? ? [ given["limit"].to_i, LOG_LIMIT ].min : LOG_LIMIT
        filters = [ { "key" => "$metadata.service", "operation" => "eq", "type" => "string", "value" => resource.external_id } ]
        filters << { "key" => "$metadata.message", "operation" => "includes", "type" => "string", "value" => given["text"] } if given["text"].present?
        filters << { "key" => "$metadata.message", "operation" => "not_includes", "type" => "string", "value" => given["exclude"] } if given["exclude"].present?
        filters << { "key" => "$metadata.message", "operation" => "regex", "type" => "string", "value" => given["regex"] } if given["regex"].present?
        # dry keeps Firefight's query out of the account's saved queries.
        body = { "queryId" => "firefight-search-logs", "view" => "events", "limit" => limit, "dry" => true, "parameters" => { "filters" => filters } }
        options = { "method" => "POST", "path" => "/accounts/#{account}/workers/observability/telemetry/query", "body" => body }
        Route.new(tool_name: EXECUTE, arguments: script(options, account, window: [ given, "request.body.timeframe = { from, to };" ]),
                  present: ->(result) { read(result) { |data| logs_result(resource, data, limit) } })
      end

      def self.metrics(resource, account, given, mapping, query, variables)
        metric_names(given, mapping, PROVIDER)
        names = Array(given["metrics"]).map(&:to_s).uniq.presence || DEFAULTS.fetch(resource.kind)
        options = { "method" => "POST", "path" => ReadGuards::Cloudflare::GRAPHQL, "body" => { "query" => query, "variables" => variables } }
        timing = "request.body.variables.start = new Date(from).toISOString(); request.body.variables.end = new Date(to).toISOString();"
        Route.new(tool_name: EXECUTE, arguments: script(options, account, window: [ given, timing ]),
                  present: lambda { |result|
                    started, ended = Telemetry.range(given, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)
                    read(result) { |data| metrics_result(resource, data, names, started, ended) }
                  })
      end

      def self.deploys(resource, account, given, path)
        limit = given["limit"].to_i.positive? ? [ given["limit"].to_i, DEPLOY_LIMIT ].min : DEPLOY_LIMIT
        Route.new(tool_name: EXECUTE, arguments: script({ "method" => "GET", "path" => path }, account),
                  present: ->(result) { read(result) { |data| deploys_result(resource, data, limit) } })
      end

      def self.history(resource, account, given, path)
        limit = given["limit"].to_i.positive? ? [ given["limit"].to_i, History::LIMIT ].min : History::LIMIT
        Route.new(tool_name: EXECUTE, arguments: script({ "method" => "GET", "path" => path }, account),
                  present: ->(result) { read(result) { |data| history_result(resource, data, given["name"], limit) } })
      end

      def self.status(resource, account, path)
        Route.new(tool_name: EXECUTE, arguments: script({ "method" => "GET", "path" => path }, account),
                  present: lambda { |result|
                    read(result) do |data|
                      said = JSON.pretty_generate(data["result"] || data).truncate(STATUS_LIMIT)
                      Telemetry.result("How #{resource.name} stands on Cloudflare now:\n#{said}", link: link(resource))
                    end
                  })
      end

      def self.change(account, options, done)
        Route.new(tool_name: EXECUTE, arguments: script(options, account),
                  present: ->(result) { read(result) { |_data| Telemetry.result(done, link: nil) } })
      end

      # The script for one request Firefight wrote, every value a JSON literal. A time range is worked out when the
      # script runs, from the minutes asked, so a call reads the same each time and a replay of a run matches it.
      # window is the request's arguments and the line that puts from and to into the request. An answer Cloudflare
      # marks as failed is thrown, so the agent, and a fix, see an error rather than a success.
      def self.script(options, account, window: nil)
        timing = window ? "#{range_js(window.first)} #{window.last} " : ""
        code = "async () => { const request = #{JSON.generate(options)}; #{timing}const answer = await cloudflare.request(request); " \
               "if (answer && (answer.success === false || (Array.isArray(answer.errors) && answer.errors.length > 0 && !answer.data))) " \
               "throw new Error(JSON.stringify(answer.errors || answer)); return answer; }"
        { ReadGuards::Cloudflare::CODE => code, ReadGuards::Cloudflare::ACCOUNT => account }
      end

      def self.range_js(given)
        ended = Telemetry.parse_time(given["end"])
        started = Telemetry.parse_time(given["start"])
        minutes = given["minutes"].to_i.positive? ? [ given["minutes"].to_i, MAX_MINUTES ].min : DEFAULT_MINUTES
        to = ended ? JSON.generate((ended.to_f * 1000).to_i) : "Date.now()"
        from = started ? JSON.generate((started.to_f * 1000).to_i) : "to - #{minutes} * 60000"
        "const to = #{to}; const from = Math.max(#{from}, to - #{MAX_MINUTES} * 60000);"
      end

      # Cloudflare's answer as data, or the answer as it came when it is an error or not JSON, so its own words reach
      # the agent rather than a guess.
      def self.read(result)
        return result if result["isError"]

        text = Array(result["content"]).filter_map { |part| part["text"] }.join
        data = JSON.parse(text)
        return result unless data.is_a?(Hash)

        yield data
      rescue JSON::ParserError
        result
      rescue StandardError => error
        # An answer in a shape the docs did not lead us to expect reaches the agent as it came.
        Rails.logger.warn({ event: "capability.unread_answer", provider: PROVIDER, error: error.class.name }.to_json)
        result
      end

      def self.logs_result(resource, data, limit)
        events = data.dig("result", "events", "events") || data.dig("result", "events")
        lines = Array(events).filter_map do |event|
          meta = event["$metadata"] || {}
          at = time_of(meta["timestamp"] || event["timestamp"])
          text = meta["message"].presence || meta["error"].presence
          Telemetry::LogLine.new(at: at, source: resource.name, text: text) if at && text
        end.sort_by(&:at).reverse
        Telemetry.result(Telemetry.logs_text(lines, asked: "Worker #{resource.name}", limit: limit), link: link(resource))
      end

      def self.metrics_result(resource, data, names, started, ended)
        bucket = bucket_minutes(started, ended)
        charts = names.map do |name|
          points = resource.kind == ResourceMap::KIND_WORKER ? worker_points(data, name, bucket) : zone_points(data, name)
          Telemetry::Chart.new(title: "#{TITLES.fetch(name, name)} of #{resource.name}", unit: UNITS.fetch(name, "count"),
                               series: [ Telemetry::Series.new(label: resource.name, points: points) ], from: started, to: ended, link: resource.url)
        end
        every = resource.kind == ResourceMap::KIND_ZONE ? "hour" : "#{bucket} minutes"
        rows = Array(data.dig("data", "viewer", "accounts", 0, "workersInvocationsAdaptive")).size
        cut = rows >= ROWS ? " Cloudflare answered with its most of #{ROWS} rows, so later points may be missing. Narrow the range to see them." : ""
        Telemetry.result("#{Telemetry.charts_text(charts)}\nCounted every #{every}.#{cut}", link: link(resource), charts: charts)
      end

      def self.worker_points(data, name, bucket)
        rows = Array(data.dig("data", "viewer", "accounts", 0, "workersInvocationsAdaptive"))
        grouped = rows.group_by { |row| floor(time_of(row.dig("dimensions", "datetime")), bucket) }.except(nil)
        grouped.sort.map do |at, members|
          value = if name == "cpu_time"
            members.sum { |row| row.dig("quantiles", "cpuTimeP50").to_f } / members.size / 1000.0
          else
            members.sum { |row| row.dig("sum", WORKER_METRICS.fetch(name)).to_f }
          end
          [ at, value ]
        end
      end

      def self.zone_points(data, name)
        rows = Array(data.dig("data", "viewer", "zones", 0, ZONE_METRICS.fetch(name)))
        rows.filter_map { |row| (at = time_of(row.dig("dimensions", "datetimeHour"))) && [ at, row["count"].to_f ] }.sort_by(&:first)
      end

      def self.deploys_result(resource, data, limit)
        listed = data["result"].is_a?(Hash) ? data.dig("result", "deployments") : data["result"]
        rows = Array(listed).first(limit).map { |deployment| deploy_line(resource, deployment) }
        return Telemetry.result("#{resource.name} has no deployments.", link: link(resource)) if rows.empty?

        to = resource.kind == ResourceMap::KIND_WORKER ? "a version id" : "a deployment id"
        Telemetry.result("Latest #{rows.size} deployments of #{resource.name}, newest first. rollback takes #{to}.\n#{rows.join("\n")}", link: link(resource))
      end

      # A Pages deployment's stages run queued, initialize, clone_repo, build and deploy, each with its status and when it
      # started and ended (Pages API, deployments, stages and latest_stage). It has finished once its deploy stage
      # succeeded, or any stage failed or was cancelled.
      STAGE_STATUSES = { "idle" => History::QUEUED, "active" => History::RUNNING, "failure" => History::FAILED, "canceled" => History::CANCELLED }.freeze
      LAST_STAGE = "deploy".freeze

      def self.history_result(resource, data, name, limit)
        listed = data["result"].is_a?(Hash) ? data.dig("result", "deployments") : data["result"]
        runs = Array(listed).map do |deployment|
          latest = deployment["latest_stage"] || {}
          status = if latest["status"] == "success" then latest["name"] == LAST_STAGE ? History::SUCCEEDED : History::RUNNING
          else History.status(latest["status"], STAGE_STATUSES)
          end
          started = Array(deployment["stages"]).filter_map { |stage| time_of(stage["started_on"]) }.min || time_of(deployment["created_on"])
          meta = deployment.dig("deployment_trigger", "metadata") || {}
          History::Run.new(
            id: deployment["id"], name: "#{deployment['environment'] || 'production'} deploy", status: status, started_at: started,
            finished_at: (time_of(latest["ended_on"]) if History::FINISHED.include?(status)), url: deployment["url"],
            detail: ("#{meta['commit_hash'].to_s.first(12)} #{meta['commit_message'].to_s.lines.first.to_s.strip}".strip if meta["commit_hash"])
          )
        end
        History.result(runs, what: resource.name, link: link(resource), name: name, limit: limit)
      end

      def self.deploy_line(resource, deployment)
        if resource.kind == ResourceMap::KIND_WORKER
          versions = Array(deployment["versions"]).map { |version| "version #{version['version_id']} at #{version['percentage']}%" }.join(" and ")
          message = deployment.dig("annotations", "workers/message")
          [ deployment["created_on"], "deployment #{deployment['id']}", versions.presence, ("by #{deployment['author_email']}" if deployment["author_email"]),
            ("from #{deployment['source']}" if deployment["source"]), ("\"#{message}\"" if message) ].compact.join(", ")
        else
          meta = deployment.dig("deployment_trigger", "metadata") || {}
          [ deployment["created_on"], "deployment #{deployment['id']}", deployment["environment"],
            ("#{meta['commit_hash'].to_s.first(12)} \"#{meta['commit_message'].to_s.lines.first.to_s.strip}\" on #{meta['branch']}" if meta["commit_hash"]),
            deployment.dig("latest_stage", "status") ].compact.join(", ")
        end
      end

      def self.link(resource) = resource.url.present? ? Telemetry::Link.new(provider: PROVIDER, url: resource.url) : nil

      def self.time_of(value)
        case value
        when Numeric then Time.zone.at(value > 1e11 ? value / 1000.0 : value).utc
        else Telemetry.parse_time(value)
        end
      end

      def self.bucket_minutes(started, ended)
        wanted = (ended - started) / 60.0 / POINTS
        BUCKETS.find { |minutes| minutes >= wanted } || BUCKETS.last
      end

      def self.floor(at, minutes)
        return nil unless at

        Time.zone.at((at.to_i / (minutes * 60)) * minutes * 60).utc
      end

      private_class_method :account_of, :logs, :metrics, :deploys, :status, :change, :read, :logs_result, :metrics_result,
                           :worker_points, :zone_points, :deploys_result, :deploy_line, :history, :history_result, :link, :time_of, :bucket_minutes, :floor, :script, :range_js
    end
  end
end
