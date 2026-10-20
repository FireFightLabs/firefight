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
        # A Worker's logs are what it prints and its Workers Builds' logs, a Pages project's are its deployments' build logs.
        LOGS => [ ResourceMap::KIND_WORKER, ResourceMap::KIND_SITE ],
        METRICS => [ ResourceMap::KIND_WORKER, ResourceMap::KIND_ZONE ],
        DEPLOYS => [ ResourceMap::KIND_WORKER, ResourceMap::KIND_SITE ],
        STATUS => [ ResourceMap::KIND_WORKER, ResourceMap::KIND_ZONE, ResourceMap::KIND_SITE ],
        # A Worker's deployment switches versions at once, so its runs are the builds Workers Builds makes from its
        # repository, and a Pages project's are its deployments' builds.
        HISTORY => [ ResourceMap::KIND_WORKER, ResourceMap::KIND_SITE ],
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
        in [ LOGS, ResourceMap::KIND_SITE ] then build_logs(resource, account, given)
        in [ LOGS, _ ] if given["stream"] == STREAM_BUILD then worker_build_logs(resource, account, given)
        in [ LOGS, _ ] then logs(resource, account, given)
        in [ METRICS, ResourceMap::KIND_WORKER ] then metrics(resource, account, given, WORKER_METRICS, WORKER_QUERY,
                                                              { "accountTag" => account, "scriptName" => resource.external_id })
        in [ METRICS, ResourceMap::KIND_ZONE ] then metrics(resource, account, given, ZONE_METRICS, ZONE_QUERY, { "zoneTag" => resource.external_id })
        in [ DEPLOYS, ResourceMap::KIND_WORKER ] then worker_deploys(resource, account, given)
        in [ DEPLOYS, ResourceMap::KIND_SITE ] then deploys(resource, account, given, "/accounts/#{account}/pages/projects/#{resource.external_id}/deployments")
        in [ HISTORY, ResourceMap::KIND_WORKER ] then worker_history(resource, account, given)
        in [ HISTORY, ResourceMap::KIND_SITE ] then history(resource, account, given, deployments_path(account, resource))
        in [ STATUS, ResourceMap::KIND_WORKER ] then status(resource, account, "/accounts/#{account}/workers/scripts/#{resource.external_id}/settings")
        in [ STATUS, ResourceMap::KIND_ZONE ] then status(resource, account, "/zones/#{resource.external_id}")
        in [ STATUS, ResourceMap::KIND_SITE ] then status(resource, account, "/accounts/#{account}/pages/projects/#{resource.external_id}")
        in [ ROLLBACK, ResourceMap::KIND_WORKER ]
          version = id_of(given, "version")
          change(account, { "method" => "POST", "path" => "/accounts/#{account}/workers/scripts/#{resource.external_id}/deployments",
                            "body" => { "strategy" => "percentage", "versions" => [ { "version_id" => version, "percentage" => 100 } ],
                                        "annotations" => { "workers/message" => "Rolled back to #{version} by Firefight" } } },
                 "#{resource.name} now serves version #{version} to all traffic.")
        in [ ROLLBACK, ResourceMap::KIND_SITE ]
          deployment = id_of(given, "deployment")
          change(account, { "method" => "POST", "path" => "/accounts/#{account}/pages/projects/#{resource.external_id}/deployments/#{deployment}/rollback" },
                 "#{resource.name} is rolled back to deployment #{deployment}.")
        end
      end

      # A Worker version and a Pages deployment are both known by a UUID (Cloudflare's API docs). Anything else is refused
      # before it is put in a request, since it goes into the path and could name another endpoint.
      def self.id_of(given, what)
        id = target(given)
        raise Unroutable, "Give the #{what} id recent_deploys shows." unless uuid?(id)

        id
      end

      def self.uuid?(id) = id.to_s.match?(/\A\h[\h-]*\z/)

      def self.deployments_path(account, resource) = "/accounts/#{account}/pages/projects/#{resource.external_id}/deployments"

      # A Pages deployment's own page in the dashboard, where its build log is, as Cloudflare's Git integration links it.
      def self.deployment_page(account, resource, id) = "#{MapReaders::Cloudflare::DASHBOARD}/#{account}/pages/view/#{resource.external_id}/#{id}"

      # The account a resource is in. The map keeps the account's name, and the reader writes every page address as
      # the dashboard, then the account's id (MapReaders::Cloudflare#dashboard).
      def self.account_of(resource)
        id = URI.parse(resource.url.to_s).path.split("/")[1] if resource.url.to_s.start_with?(MapReaders::Cloudflare::DASHBOARD)
        id.presence || raise(Unroutable, "The Cloudflare account of #{resource.name} is not known, so it cannot be asked for this.")
      end

      def self.logs(resource, account, given)
        if given["stream"].present? && given["stream"] != STREAM_APP
          raise Unroutable, "Cloudflare keeps what a Worker prints and the logs of its builds, so stream must be #{STREAM_APP} or #{STREAM_BUILD}."
        end

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
                  present: ->(result) { read(result) { |data| deploys_result(resource, account, data, limit) } })
      end

      # A Pages project's build log, of the deployment named, or of its newest one. A named deployment's log is one
      # request written by the read guard (ReadGuards::Cloudflare.arguments_for), the same one a run's stages carry.
      # Without a name, one script finds the newest deployment and checks its id before it goes into the path.
      def self.build_logs(resource, account, given)
        stream = given["stream"].presence
        raise Unroutable, "Cloudflare keeps a Pages project's build logs, so stream must be #{STREAM_BUILD}." if stream && stream != STREAM_BUILD

        deployment = given["deployment"].to_s.strip.presence
        raise Unroutable, "Give the deployment id run_history or recent_deploys shows." if deployment && !uuid?(deployment)

        limit = given["limit"].to_i.positive? ? [ given["limit"].to_i, LOG_LIMIT ].min : LOG_LIMIT
        arguments = deployment ? build_log_arguments(account, resource, deployment) : newest_build_log(account, resource)
        Route.new(tool_name: EXECUTE, arguments: arguments,
                  present: ->(result) { read(result) { |data| build_logs_result(resource, account, data, given, limit, deployment) } })
      end

      def self.build_log_arguments(account, resource, id)
        ReadGuards::Cloudflare.arguments_for({ "method" => ReadGuards::Cloudflare::GET, "path" => "#{deployments_path(account, resource)}/#{id}/history/logs" }, account)
      end

      def self.newest_build_log(account, resource)
        path = deployments_path(account, resource)
        code = "async () => { const listed = await cloudflare.request(#{JSON.generate('method' => 'GET', 'path' => path)}); " \
               "const newest = (Array.isArray(listed && listed.result) ? listed.result : [])[0]; if (!newest) return { result: null }; " \
               "if (!/^[0-9a-f-]+$/i.test(String(newest.id))) throw new Error(\"Unexpected deployment id\"); " \
               "const answer = await cloudflare.request({ method: \"GET\", path: #{JSON.generate(path)} + \"/\" + newest.id + \"/history/logs\" }); " \
               "if (answer && answer.success === false) throw new Error(JSON.stringify(answer.errors || answer)); " \
               "return Object.assign({}, answer, { deployment: newest.id }); }"
        { ReadGuards::Cloudflare::CODE => code, ReadGuards::Cloudflare::ACCOUNT => account }
      end

      # The Pages API answers a deployment's log as lines with their time, oldest first (deployments, get logs).
      def self.build_logs_result(resource, account, data, given, limit, deployment)
        id = deployment || data["deployment"]
        return Telemetry.result("#{resource.name} has no deployments, so it has no build log.", link: link(resource)) if id.blank?

        matcher = log_matcher(given)
        lines = Array(data.dig("result", "data")).filter_map do |entry|
          text = entry["line"].to_s
          Telemetry::LogLine.new(at: time_of(entry["ts"]) || Time.current, source: id, text: text) if text.present? && matcher.call(text)
        end.sort_by(&:at).reverse
        Telemetry.result(Telemetry.logs_text(lines.first(limit), asked: "the build of deployment #{id} of #{resource.name}", limit: limit),
                         link: Telemetry::Link.new(provider: PROVIDER, url: deployment_page(account, resource, id)))
      end

      def self.log_matcher(given)
        text = given["text"].to_s.downcase.presence
        exclude = given["exclude"].to_s.downcase.presence
        regex = given["regex"].presence && Regexp.new(given["regex"], Regexp::IGNORECASE, timeout: 1)
        lambda do |line|
          lowered = line.downcase
          (text.nil? || lowered.include?(text)) && (exclude.nil? || !lowered.include?(exclude)) && (regex.nil? || regex.match?(line))
        end
      rescue RegexpError => error
        raise Unroutable, "regex is not a regular expression: #{error.message}"
      end

      def self.history(resource, account, given, path)
        run = given["run"].to_s.strip.delete_prefix("#").presence
        return one_run(resource, account, run, path) if run

        limit = given["limit"].to_i.positive? ? [ given["limit"].to_i, History::LIMIT ].min : History::LIMIT
        Route.new(tool_name: EXECUTE, arguments: script({ "method" => "GET", "path" => path }, account),
                  present: ->(result) { read(result) { |data| history_result(resource, account, data, given["name"], limit) } })
      end

      # One deployment by its id, whatever its age, with its stages as parts, each reading that deployment's build log.
      def self.one_run(resource, account, id, path)
        raise Unroutable, "run is a Pages deployment's id, as run_history shows it." unless uuid?(id)

        Route.new(tool_name: EXECUTE, arguments: script({ "method" => "GET", "path" => "#{path}/#{id}" }, account),
                  present: lambda { |result|
                    read(result) do |data|
                      deployment = data["result"]
                      next Telemetry.result("Cloudflare has no deployment #{id} of #{resource.name}.", link: link(resource)) unless deployment.is_a?(Hash)

                      run = history_run(resource, account, deployment)
                      parts = Array(deployment["stages"]).map { |stage| stage_part(resource, account, deployment["id"], stage) }
                      History.result([ run.with(parts: parts) ], what: resource.name, link: Telemetry::Link.new(provider: PROVIDER, url: run.url))
                    end
                  })
      end

      def self.stage_part(resource, account, id, stage)
        status = History.status(stage["status"], STAGE_STATUSES)
        History::Part.new(
          id: stage["name"], name: stage["name"], status: status, started_at: time_of(stage["started_on"]),
          finished_at: (time_of(stage["ended_on"]) if History::FINISHED.include?(status)), url: deployment_page(account, resource, id),
          log: { History::LOG_TOOL => EXECUTE, History::LOG_ARGUMENTS => build_log_arguments(account, resource, id) }
        )
      end

      # Workers Builds knows a Worker by its tag rather than its name (Workers Builds API reference, Get your Worker tag).
      # The map keeps it, and a Worker read before it did has it looked up in the account's Workers first. Either way it
      # is checked before it goes into a path.
      def self.worker_tag_js(account, resource)
        known = resource.details.to_h[MapReaders::Cloudflare::WORKER_TAG].to_s
        return "const tag = #{JSON.generate(known)};" if known.match?(BUILD_ID)

        "const scripts = await cloudflare.request(#{JSON.generate('method' => 'GET', 'path' => "/accounts/#{account}/workers/scripts")}); " \
          "const script = (Array.isArray(scripts && scripts.result) ? scripts.result : []).find((each) => each.id === #{JSON.generate(resource.external_id)}); " \
          "if (!script) throw new Error(#{JSON.generate("Cloudflare has no Worker #{resource.external_id}")}); " \
          "if (!/^[0-9a-f-]+$/i.test(String(script.tag))) throw new Error(\"Unexpected Worker tag\"); const tag = script.tag;"
      end

      # A script of Firefight's own: the Worker's tag, then body, with every answer Cloudflare marks as failed thrown.
      def self.worker_script(account, resource, body)
        code = "async () => { const ask = async (request) => { const answer = await cloudflare.request(request); " \
               "if (answer && answer.success === false) throw new Error(JSON.stringify(answer.errors || answer)); return answer; }; " \
               "#{worker_tag_js(account, resource).gsub('await cloudflare.request(', 'await ask(')} #{body} }"
        { ReadGuards::Cloudflare::CODE => code, ReadGuards::Cloudflare::ACCOUNT => account }
      end

      def self.builds_path(account) = "/accounts/#{account}/builds"

      # The Worker's builds, newest first, or one build by its id with what Cloudflare says of it, whatever its age.
      def self.worker_history(resource, account, given)
        run = given["run"].to_s.strip.delete_prefix("#").presence
        if run
          raise Unroutable, "run is a Workers build's id, as run_history shows it." unless uuid?(run)

          body = "const answer = await ask(#{JSON.generate('method' => 'GET', 'path' => "#{builds_path(account)}/builds/#{run}")}); return { result: answer.result, tag };"
          return Route.new(tool_name: EXECUTE, arguments: worker_script(account, resource, body),
                           present: ->(result) { read(result) { |data| worker_run_result(resource, account, data, run) } })
        end

        limit = given["limit"].to_i.positive? ? [ given["limit"].to_i, History::LIMIT ].min : History::LIMIT
        body = "const answer = await ask({ method: \"GET\", path: #{JSON.generate("#{builds_path(account)}/workers/")} + tag + \"/builds\", " \
               "query: { per_page: #{History::LIMIT} } }); return { result: answer.result };"
        Route.new(tool_name: EXECUTE, arguments: worker_script(account, resource, body),
                  present: lambda { |result|
                    read(result) do |data|
                      runs = Array(data["result"]).map { |build| worker_run(resource, account, build) }
                      History.result(runs, what: resource.name, link: link(resource), name: given["name"], limit: limit)
                    end
                  })
      end

      def self.worker_run_result(resource, account, data, id)
        build = data["result"]
        built_for = build.is_a?(Hash) ? build.dig("trigger", "external_script_id") : nil
        unless build.is_a?(Hash) && (built_for.blank? || built_for == data["tag"])
          return Telemetry.result("Cloudflare has no build #{id} of #{resource.name}.", link: link(resource))
        end

        run = worker_run(resource, account, build)
        History.result([ run ], what: resource.name, link: Telemetry::Link.new(provider: PROVIDER, url: run.url))
      end

      # A build is queued, initializing, running or stopped, and once stopped its outcome says how it ended (Workers
      # Builds API, list builds, status and build_outcome). Skipped is a build that never ran.
      BUILD_STATUSES = { "queued" => History::QUEUED, "initializing" => History::RUNNING, "running" => History::RUNNING }.freeze
      BUILD_OUTCOMES = { "success" => History::SUCCEEDED, "fail" => History::FAILED, "terminated" => History::FAILED,
                         "cancelled" => History::CANCELLED, "skipped" => History::CANCELLED }.freeze
      BUILD_STOPPED = "stopped".freeze
      # A Workers build id is a UUID, and a Worker's tag is hex.
      BUILD_ID = /\A\h[\h-]*\z/

      def self.worker_run(resource, account, build)
        status = if build["status"] == BUILD_STOPPED then History.status(build["build_outcome"], BUILD_OUTCOMES)
        else History.status(build["status"], BUILD_STATUSES)
        end
        meta = build["build_trigger_metadata"] || {}
        History::Run.new(
          id: build["build_uuid"], name: "#{meta['branch'].presence || 'worker'} build", status: status, started_at: time_of(build["created_on"]),
          finished_at: (time_of(build["stopped_on"]) if History::FINISHED.include?(status)), url: worker_builds_page(account, resource),
          detail: ("#{meta['commit_hash'].to_s.first(12)} #{meta['commit_message'].to_s.lines.first.to_s.strip}".strip if meta["commit_hash"])
        )
      end

      # A Worker's build history is at the bottom of its Deployments tab (Workers Builds, View build and Preview URL).
      def self.worker_builds_page(account, resource)
        "#{MapReaders::Cloudflare::DASHBOARD}/#{account}/workers/services/view/#{Http.segment(resource.external_id)}/production/deployments"
      end

      BUILD_LOG_PAGES = 10

      # A Workers build's log, of the build named, or of the Worker's newest one. Cloudflare answers it a page at a time,
      # each line its time and its text, with a cursor to the next (Workers Builds API, get build logs).
      def self.worker_build_logs(resource, account, given)
        build = given["deployment"].to_s.strip.presence || given["run"].to_s.strip.presence
        raise Unroutable, "Give the build id run_history shows." if build && !uuid?(build)

        limit = given["limit"].to_i.positive? ? [ given["limit"].to_i, LOG_LIMIT ].min : LOG_LIMIT
        find = if build then "const build = #{JSON.generate(build)};"
        else
          "const listed = await ask({ method: \"GET\", path: #{JSON.generate("#{builds_path(account)}/workers/")} + tag + \"/builds\", query: { per_page: 1 } }); " \
            "const newest = (Array.isArray(listed.result) ? listed.result : [])[0]; if (!newest) return { result: null }; " \
            "if (!/^[0-9a-f-]+$/i.test(String(newest.build_uuid))) throw new Error(\"Unexpected build id\"); const build = newest.build_uuid;"
        end
        body = "#{find} const lines = []; let cursor = null; let truncated = false; " \
               "for (let page = 0; page < #{BUILD_LOG_PAGES}; page++) { " \
               "const answer = await ask({ method: \"GET\", path: #{JSON.generate("#{builds_path(account)}/builds/")} + build + \"/logs\", query: cursor ? { cursor } : {} }); " \
               "const read = (answer && answer.result) || {}; const got = Array.isArray(read.lines) ? read.lines : []; lines.push(...got); " \
               "truncated = Boolean(read.truncated); if (!read.cursor || got.length === 0) { cursor = null; break; } cursor = read.cursor; } " \
               "return { result: { lines, truncated, more: Boolean(cursor) }, build };"
        Route.new(tool_name: EXECUTE, arguments: worker_script(account, resource, body),
                  present: ->(result) { read(result) { |data| worker_build_logs_result(resource, account, data, given, limit) } })
      end

      def self.worker_build_logs_result(resource, account, data, given, limit)
        id = data["build"]
        return Telemetry.result("#{resource.name} has no Workers builds, so it has no build log.", link: link(resource)) if id.blank?

        matcher = log_matcher(given)
        lines = Array(data.dig("result", "lines")).filter_map do |entry|
          at, text = Array(entry)
          Telemetry::LogLine.new(at: time_of(at) || Time.current, source: id, text: text.to_s) if text.present? && matcher.call(text.to_s)
        end.sort_by(&:at).reverse
        cut = data.dig("result", "truncated") || data.dig("result", "more") ? "\nCloudflare holds more of this log than was read." : ""
        Telemetry.result("#{Telemetry.logs_text(lines.first(limit), asked: "build #{id} of #{resource.name}", limit: limit)}#{cut}",
                         link: Telemetry::Link.new(provider: PROVIDER, url: worker_builds_page(account, resource)))
      end

      # A Worker's deployments, and its versions beside them, since a version uploaded and not yet deployed, or one held
      # at a share of traffic, is what changed next (Workers API, list deployments and list versions).
      def self.worker_deploys(resource, account, given)
        limit = given["limit"].to_i.positive? ? [ given["limit"].to_i, DEPLOY_LIMIT ].min : DEPLOY_LIMIT
        path = "/accounts/#{account}/workers/scripts/#{resource.external_id}"
        code = "async () => { const ask = async (request) => { const answer = await cloudflare.request(request); " \
               "if (answer && answer.success === false) throw new Error(JSON.stringify(answer.errors || answer)); return answer; }; " \
               "const deployments = await ask(#{JSON.generate('method' => 'GET', 'path' => "#{path}/deployments")}); " \
               "const versions = await ask(#{JSON.generate('method' => 'GET', 'path' => "#{path}/versions", 'query' => { 'per_page' => DEPLOY_LIMIT })}); " \
               "return { result: deployments.result, versions: versions.result }; }"
        Route.new(tool_name: EXECUTE, arguments: { ReadGuards::Cloudflare::CODE => code, ReadGuards::Cloudflare::ACCOUNT => account },
                  present: lambda { |result|
                    read(result) do |data|
                      versions = Array(data.dig("versions", "items")).first(limit)
                      deployed = Array(data.dig("result", "deployments")).flat_map { |deployment| Array(deployment["versions"]).map { |version| version["version_id"] } }
                      said = if versions.any?
                        "Latest #{versions.size} versions, newest first. A version in no deployment listed was uploaded and has not served.\n" \
                          "#{versions.map { |version| version_line(version, deployed) }.join("\n")}"
                      end
                      deploys_result(resource, account, data, limit, versions: said)
                    end
                  })
      end

      def self.version_line(version, deployed)
        meta = version["metadata"] || {}
        [ meta["created_on"], "version #{version['id']}", ("number #{version['number']}" if version["number"]), ("by #{meta['author_email']}" if meta["author_email"]),
          ("from #{meta['source']}" if meta["source"]), (deployed.include?(version["id"]) ? "deployed" : "in no deployment listed") ].compact.join(", ")
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

      # versions is what a Worker's versions add, said after its deployments.
      def self.deploys_result(resource, account, data, limit, versions: nil)
        listed = data["result"].is_a?(Hash) ? data.dig("result", "deployments") : data["result"]
        shown = Array(listed).first(limit)
        rows = shown.map { |deployment| deploy_line(resource, deployment) }
        return Deploys.with_deploys(Telemetry.result([ "#{resource.name} has no deployments.", versions ].compact.join("\n"), link: link(resource)), []) if rows.empty?

        to = resource.kind == ResourceMap::KIND_WORKER ? "a version id" : "a deployment id"
        said = [ "Latest #{rows.size} deployments of #{resource.name}, newest first. rollback takes #{to}.", *rows, versions ].compact.join("\n")
        result = Telemetry.result(said, link: link(resource))
        deploys = if resource.kind == ResourceMap::KIND_WORKER
          shown.map { |deployment| worker_deploy(deployment, serving: deployment.equal?(shown.first)) }
        else
          shown.map { |deployment| pages_deploy(resource, account, deployment) }
        end
        Deploys.with_deploys(result, deploys)
      end

      # The first of a Worker's deployments is the one serving traffic (Workers API, list deployments). A deployment
      # switches its versions in at once, so it finished when it was made.
      def self.worker_deploy(deployment, serving:)
        versions = Array(deployment["versions"]).sort_by { |version| -version["percentage"].to_f }.filter_map { |version| version["version_id"].presence }
        made = time_of(deployment["created_on"])
        Deploys::Deploy.new(id: deployment["id"], version: versions.join(","), status: History::SUCCEEDED, live: serving, started_at: made, finished_at: made)
      end

      # A Pages deployment's state as its run history reads it. The list does not say which production deployment
      # serves, so after a rollback the newest finished one is still taken as live. A preview one never serves the
      # project's own address.
      def self.pages_deploy(resource, account, deployment)
        run = history_run(resource, account, deployment)
        meta = deployment.dig("deployment_trigger", "metadata") || {}
        Deploys::Deploy.new(id: deployment["id"], commit: meta["commit_hash"], branch: meta["branch"], status: run.status,
                            live: (false if deployment["environment"] == PREVIEW), started_at: run.started_at, finished_at: run.finished_at,
                            environment: deployment["environment"])
      end

      # A Pages deployment's stages run queued, initialize, clone_repo, build and deploy, each with its status and when it
      # started and ended (Pages API, deployments, stages and latest_stage). It has finished once its deploy stage
      # succeeded, or any stage failed or was cancelled.
      STAGE_STATUSES = { "idle" => History::QUEUED, "active" => History::RUNNING, "success" => History::SUCCEEDED, "failure" => History::FAILED,
                         "canceled" => History::CANCELLED }.freeze
      LAST_STAGE = "deploy".freeze
      PREVIEW = "preview".freeze

      def self.history_result(resource, account, data, name, limit)
        listed = data["result"].is_a?(Hash) ? data.dig("result", "deployments") : data["result"]
        runs = Array(listed).map { |deployment| history_run(resource, account, deployment) }
        History.result(runs, what: resource.name, link: link(resource), name: name, limit: limit)
      end

      def self.history_run(resource, account, deployment)
        latest = deployment["latest_stage"] || {}
        status = if latest["status"] == "success" then latest["name"] == LAST_STAGE ? History::SUCCEEDED : History::RUNNING
        else History.status(latest["status"], STAGE_STATUSES)
        end
        started = Array(deployment["stages"]).filter_map { |stage| time_of(stage["started_on"]) }.min || time_of(deployment["created_on"])
        meta = deployment.dig("deployment_trigger", "metadata") || {}
        History::Run.new(
          id: deployment["id"], name: "#{deployment['environment'] || 'production'} deploy", status: status, started_at: started,
          finished_at: (time_of(latest["ended_on"]) if History::FINISHED.include?(status)), url: deployment_page(account, resource, deployment["id"]),
          detail: ("#{meta['commit_hash'].to_s.first(12)} #{meta['commit_message'].to_s.lines.first.to_s.strip}".strip if meta["commit_hash"])
        )
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

      private_class_method :account_of, :logs, :build_logs, :worker_tag_js, :worker_script, :builds_path, :worker_history, :worker_run_result, :worker_run,
                           :worker_builds_page, :worker_build_logs, :worker_build_logs_result, :worker_deploys, :version_line, :build_log_arguments, :newest_build_log, :build_logs_result, :log_matcher,
                           :one_run, :stage_part, :history_run, :uuid?, :deployments_path, :deployment_page, :metrics, :deploys, :status, :change, :read, :logs_result, :metrics_result,
                           :worker_points, :zone_points, :deploys_result, :worker_deploy, :pages_deploy, :deploy_line, :history, :history_result, :link, :time_of, :bucket_minutes, :floor, :script, :range_js
    end
  end
end
