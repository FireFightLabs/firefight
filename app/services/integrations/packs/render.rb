module Integrations
  module Packs
    # Render for one workspace per environment: its services, Postgres databases and Key Value instances, their logs,
    # metrics, deploys and events, read with the API key the workspace's owner creates in Render. Every tool reads,
    # except the restart, rollback and scale an admin switches on for Halon to apply fixes. Paths, parameters and
    # answers are the ones in Render's OpenAPI spec (api-docs.render.com/openapi/render-public-api-1.json).
    class Render < NativePack
      # The environment row's credentials, which only this pack reads.
      API_KEY = "api_key".freeze
      WORKSPACE = "workspace".freeze

      PROVIDER = "Render".freeze
      PROVIDER_KEY = "render".freeze

      # Render's service types (spec, schema serviceType), and how each sits on the map.
      WEB_SERVICE = "web_service".freeze
      PRIVATE_SERVICE = "private_service".freeze
      BACKGROUND_WORKER = "background_worker".freeze
      CRON_JOB = "cron_job".freeze
      STATIC_SITE = "static_site".freeze
      POSTGRES = "postgres".freeze
      KEY_VALUE = "key_value".freeze
      KINDS = {
        WEB_SERVICE => ResourceMap::KIND_SERVICE, PRIVATE_SERVICE => ResourceMap::KIND_SERVICE, BACKGROUND_WORKER => ResourceMap::KIND_SERVICE,
        CRON_JOB => ResourceMap::KIND_JOB, STATIC_SITE => ResourceMap::KIND_SITE, POSTGRES => ResourceMap::KIND_DATABASE,
        KEY_VALUE => ResourceMap::KIND_DATABASE
      }.freeze
      TYPE_WORDS = {
        WEB_SERVICE => "web service", PRIVATE_SERVICE => "private service", BACKGROUND_WORKER => "background worker",
        CRON_JOB => "cron job", STATIC_SITE => "static site", POSTGRES => "Postgres database", KEY_VALUE => "Key Value instance"
      }.freeze
      DATASTORES = [ POSTGRES, KEY_VALUE ].freeze
      # Render scales web services, private services and background workers (render.com/docs/scaling).
      SCALABLE = [ WEB_SERVICE, PRIVATE_SERVICE, BACKGROUND_WORKER ].freeze
      # The restart endpoint is not supported for cron jobs (spec, POST /services/{serviceId}/restart), and a static
      # site runs no instance to restart.
      RESTARTABLE = [ WEB_SERVICE, PRIVATE_SERVICE, BACKGROUND_WORKER, POSTGRES ].freeze
      SUSPENDED = "suspended".freeze

      # The log types Render names (spec, GET /logs type): app for what the code prints, request for HTTP requests
      # reaching a web service on a Pro workspace or higher, build for builds.
      LOG_TYPES = %w[app request build].freeze
      # Render answers at most 100 lines a call (spec, GET /logs limit).
      LOG_LIMIT = 100
      DEPLOY_LIMIT = 20
      EVENT_LIMIT = 50
      EVENT_MINUTES = 24 * 60
      RECENT_EVENTS = 10

      # Each metric a tool takes, the endpoint that answers it and what it applies to. HTTP metrics are kept for web
      # services only and active connections for datastores only (spec, paths /metrics/*).
      Metric = Data.define(:path, :title, :applies, :query) do
        def initialize(query: {}, **) = super
      end
      COMPUTE = [ WEB_SERVICE, PRIVATE_SERVICE, BACKGROUND_WORKER, CRON_JOB, *DATASTORES ].freeze
      METRICS = {
        "cpu" => Metric.new(path: "cpu", title: "CPU", applies: COMPUTE),
        "memory" => Metric.new(path: "memory", title: "Memory", applies: COMPUTE),
        "requests" => Metric.new(path: "http-requests", title: "Requests", applies: [ WEB_SERVICE ]),
        "http_4xx" => Metric.new(path: "http-requests", title: "4xx responses", applies: [ WEB_SERVICE ], query: { "aggregateBy" => "statusCode" }),
        "http_5xx" => Metric.new(path: "http-requests", title: "5xx responses", applies: [ WEB_SERVICE ], query: { "aggregateBy" => "statusCode" }),
        "active_connections" => Metric.new(path: "active-connections", title: "Active connections", applies: DATASTORES)
      }.freeze
      STATUS_CLASSES = { "http_4xx" => "4", "http_5xx" => "5" }.freeze
      DEFAULT_METRICS = { WEB_SERVICE => %w[cpu memory requests http_5xx], POSTGRES => %w[cpu memory active_connections],
                          KEY_VALUE => %w[cpu memory active_connections] }.freeze
      FALLBACK_METRICS = %w[cpu memory].freeze
      # What a baseline reads. Request counts are left out, since the spec does not say what span each reading counts.
      BASELINE_METRICS = %w[cpu memory active_connections].freeze
      # Render takes 30 seconds or more between readings (spec, resolutionSeconds), and about this many points reads well.
      MIN_RESOLUTION = 30
      POINTS = 60
      BASELINE_RESOLUTION = 3600
      STATUS_CODE = /\A[1-5]\d\d\z/

      RESOURCE = { "type" => "string", "description" => "A service, Postgres database or Key Value instance in the workspace, by name or id, as list_resources shows it" }.freeze

      tool :list_resources,
           description: "The services, Postgres databases and Key Value instances in the Render workspace for this environment, " \
                        "with their type and whether each is running or suspended. Use it first to find the name to pass to the other tools",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :describe_resource,
           description: "How one service or datastore is set up and how it stands now. A service: whether it is suspended and why, " \
                        "its plan, region, instances or autoscaling, what it runs, its health check path, its latest deploy and " \
                        "its events of the last day. A datastore: its status, version, plan, disk, high availability and maintenance",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: true

      tool :search_logs,
           description: "Log lines from one service or datastore, newest first, at most #{LOG_LIMIT}. Filter by text or a regular " \
                        "expression, and by type: app for what the code prints, request for HTTP requests reaching a web " \
                        "service (Pro workspaces and higher), build for its builds",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "regex" => { "type" => "string", "description" => "Only lines matching this regular expression, in RE2 syntax (optional)" },
               "type" => { "type" => "string", "enum" => LOG_TYPES, "description" => "Which logs (optional, every type)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :query_metrics,
           description: "Metrics of one service or datastore over time: CPU and memory, and for a web service requests and 4xx " \
                        "and 5xx responses, and for a datastore its active connections. " \
                        "Returns min, average, max and latest per instance, and the person sees each metric as a chart",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "metrics" => { "type" => "array", "items" => { "type" => "string", "enum" => METRICS.keys },
                              "description" => "Which metrics (optional, the usual ones for the resource)" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :list_deployments,
           description: "A service's deploys, newest first: when each started and finished, its status, the commit or image, and " \
                        "what triggered it (a new commit, a rollback, a manual deploy). The id of a live deploy is what " \
                        "rollback_deploy takes. Use it to see what changed before something broke",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "limit" => { "type" => "integer", "description" => "At most this many deploys (optional, #{DEPLOY_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :list_events,
           description: "A service's events, newest first: instances that failed and why (ran out of memory, exited, failed health " \
                        "checks, timed out), restarts, deploys and builds that ended, scaling, disk usage warnings and suspensions. " \
                        "Use it when instances crash or restart",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "limit" => { "type" => "integer", "description" => "At most this many events (optional, #{EVENT_LIMIT})" },
               "minutes" => { "type" => "integer", "description" => "How far back from now, in minutes (optional, #{EVENT_MINUTES})" },
               "start" => Capabilities::RANGE["start"], "end" => Capabilities::RANGE["end"]
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :restart_service,
           description: "Restart a web service, private service, background worker or Postgres database. Render replaces every " \
                        "instance with the same code and settings, without downtime for a service, and does not pick up " \
                        "environment changes made since the last deploy",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: false

      tool :rollback_deploy,
           description: "Put a service back on an earlier deploy, by the deploy id list_deployments shows. Render puts that " \
                        "build back live without building again, while it still keeps the build. Autodeploy stays on, so the " \
                        "next commit deploys again",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "deploy" => { "type" => "string", "description" => "The deploy to go back to, by its id, such as dep-..." }
             },
             "required" => %w[resource deploy]
           },
           read_only: false

      tool :scale_service,
           description: "Set how many instances a web service, private service or background worker runs. Render ignores it " \
                        "while autoscaling is on for the service",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "instances" => { "type" => "integer", "description" => "How many instances to run" }
             },
             "required" => %w[resource instances]
           },
           read_only: false

      def self.credential_fields
        [
          CredentialField.new(key: API_KEY, label: "API key", secret: true, placeholder: "rnd_...",
                              hint: "A Render API key, created under Account Settings, API Keys. It acts with the access of the person who created it.")
        ]
      end

      # Reads the workspace with the key, so a wrong key or workspace is said on the form before anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        key = values[API_KEY].to_s.strip
        workspace = fields[WORKSPACE].to_s.strip
        return "Paste an API key." if key.empty?
        return "Enter the workspace id." if workspace.empty?

        RenderApi.new(key).owner(workspace)
        nil
      rescue RenderApi::Error => error
        Sentence.join("Render refused this key or workspace", error)
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_KEY, values[API_KEY].to_s.strip)
      end

      def list_resources(environment_row:, arguments:)
        rows = resources(environment_row).map { |resource| "#{resource[:name]} (#{resource[:id]}), #{TYPE_WORDS.fetch(resource[:type])}, #{resource[:status]}" }
        text = rows.empty? ? "Workspace #{workspace_of(environment_row)} has no services or datastores." : "#{rows.size} services and datastores.\n#{rows.join("\n")}"
        Telemetry.result(text, link: nil)
      end

      def describe_resource(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        lines = case resource[:type]
        when POSTGRES then postgres_lines(environment_row, resource)
        when KEY_VALUE then key_value_lines(environment_row, resource)
        else service_lines(environment_row, resource)
        end
        Telemetry.result(lines.compact.join("\n"), link: link(resource))
      end

      def search_logs(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        started, ended = Capabilities::Answers.range(arguments)
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        # A regular expression goes in text between slashes, as Render's log search reads one.
        texts = [ arguments["text"].presence, (arguments["regex"].present? ? "/#{arguments['regex']}/" : nil) ].compact
        query = {
          "ownerId" => workspace_of(environment_row), "resource" => resource[:id], "startTime" => started.utc.iso8601,
          "endTime" => ended.utc.iso8601, "direction" => "backward", "limit" => limit, "text" => texts.presence,
          "type" => arguments["type"].presence_in(LOG_TYPES)
        }
        answer = api(environment_row).logs(query)
        lines = Array(answer["logs"]).map do |line|
          instance = Array(line["labels"]).find { |label| label["name"] == "instance" }&.dig("value")
          Telemetry::LogLine.new(at: Telemetry.parse_time(line["timestamp"]) || ended, source: instance.to_s, text: line["message"])
        end
        asked = "#{resource[:name]} from #{started.utc.iso8601} to #{ended.utc.iso8601}"
        # Render says when older lines in the range were left out, so the text says they were only then.
        shown_limit = answer["hasMore"] ? lines.size : lines.size + 1
        Telemetry.result(Telemetry.logs_text(lines, asked: asked, limit: shown_limit), link: link(resource))
      end

      def query_metrics(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        fail! "#{resource[:name]} is a static site, and Render keeps no metrics for one." if resource[:type] == STATIC_SITE

        started, ended = Capabilities::Answers.range(arguments)
        asked = Array(arguments["metrics"]).map(&:to_s) & METRICS.keys
        asked = DEFAULT_METRICS.fetch(resource[:type], FALLBACK_METRICS) if asked.empty?
        kept, missing = asked.partition { |name| METRICS.fetch(name).applies.include?(resource[:type]) }
        resolution = [ ((ended - started) / POINTS).ceil, MIN_RESOLUTION ].max
        charts = kept.map { |name| chart(environment_row, resource, name, started, ended, resolution) }
        note = missing.any? ? "\nRender does not keep #{missing.join(', ')} for a #{TYPE_WORDS.fetch(resource[:type])}." : ""
        Telemetry.result("#{resource[:name]}\n#{Telemetry.charts_text(charts)}#{note}", charts: charts, link: link(resource))
      end

      def list_deployments(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        fail! "#{resource[:name]} is a datastore, and only services have deploys." if DATASTORES.include?(resource[:type])

        deploys = api(environment_row).deploys(resource[:id], limit: Capabilities::Answers.limit(arguments, DEPLOY_LIMIT))
        return Telemetry.result("#{resource[:name]} has no deploys.", link: link(resource)) if deploys.empty?

        rows = deploys.map { |deploy| deploy_line(resource, deploy) }
        Telemetry.result("Latest #{rows.size} deploys of #{resource[:name]}, newest first. rollback_deploy takes a deploy id.\n#{rows.join("\n")}", link: link(resource))
      end

      def list_events(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        fail! "#{resource[:name]} is a datastore, and Render lists events for services only." if DATASTORES.include?(resource[:type])

        started, ended = Telemetry.range(arguments, default_minutes: EVENT_MINUTES, max_minutes: Capabilities::MAX_MINUTES)
        events = api(environment_row).events(resource[:id], "startTime" => started.utc.iso8601, "endTime" => ended.utc.iso8601,
                                                            "limit" => Capabilities::Answers.limit(arguments, EVENT_LIMIT))
        return Telemetry.result("#{resource[:name]} had no events from #{started.utc.iso8601} to #{ended.utc.iso8601}.", link: link(resource)) if events.empty?

        rows = events.map { |event| event_line(event) }
        Telemetry.result("#{rows.size} events of #{resource[:name]}, newest first.\n#{rows.join("\n")}", link: link(resource))
      end

      def restart_service(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        unless RESTARTABLE.include?(resource[:type])
          fail! "Render cannot restart a #{TYPE_WORDS.fetch(resource[:type])} through its API. Redeploy it in Render instead."
        end

        resource[:type] == POSTGRES ? api(environment_row).restart_postgres(resource[:id]) : api(environment_row).restart_service(resource[:id])
        Telemetry.result("Render is restarting #{resource[:name]}. Its events show when the new instances are up.", link: link(resource))
      end

      def rollback_deploy(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        fail! "#{resource[:name]} is a datastore, and only services have deploys to roll back to." if DATASTORES.include?(resource[:type])
        deploy = arguments["deploy"].to_s.strip
        fail! "Say which deploy to go back to, by the id list_deployments shows." if deploy.empty?

        started = api(environment_row).rollback(resource[:id], deploy)
        Telemetry.result("Render is rolling #{resource[:name]} back to deploy #{deploy}#{", as deploy #{started['id']}" if started['id']}. " \
                         "Autodeploy is still on, so the next commit to its branch deploys again. Turn autodeploy off in Render " \
                         "if the rollback should stay.", link: link(resource))
      end

      def scale_service(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        unless SCALABLE.include?(resource[:type])
          fail! "Render scales web services, private services and background workers, and #{resource[:name]} is a #{TYPE_WORDS.fetch(resource[:type])}."
        end
        count = Integer(arguments["instances"], exception: false)
        fail! "instances must be a whole number, 0 or more." unless count && count >= 0

        service = api(environment_row).service(resource[:id])
        if service.dig("serviceDetails", "autoscaling", "enabled")
          fail! "Autoscaling is on for #{resource[:name]}, and Render ignores a set number of instances while it is. Change its " \
                "autoscaling minimum and maximum in Render instead."
        end

        api(environment_row).scale(resource[:id], count)
        before = service.dig("serviceDetails", "numInstances")
        Telemetry.result("Render is scaling #{resource[:name]} to #{count} instances#{" from #{before}" if before}.", link: link(resource))
      end

      # The workspace on the resource map: its services, sites, cron jobs and datastores, the repositories services build
      # from and the domains they serve. What could not be read for one service is a gap, not a failed sweep.
      def map_of(environment_row)
        api = api(environment_row)
        account = workspace_of(environment_row)
        reading = MapReading.new(account)
        gaps = []
        services = api.services(account)
        bounded(services, "services", [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_JOB, ResourceMap::KIND_SITE, ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ], gaps)
        services.items.each do |service|
          deploy = begin
            api.deploys(service["id"], limit: 1).first
          rescue Integrations::RateLimited
            raise
          rescue RenderApi::Error => error
            gaps << ResourceMap::Gap.new(text: Sentence.join("The latest deploy of #{service['name']} could not be read", error), kinds: [])
            nil
          end
          found = reading.service(service, deploy)
          next unless [ WEB_SERVICE, STATIC_SITE ].include?(service["type"])

          begin
            domains = api.custom_domains(service["id"])
            bounded(domains, "custom domains of #{service['name']}", [ ResourceMap::KIND_DOMAIN ], gaps)
            domains.items.each { |domain| reading.domain(found, domain["name"]) }
          rescue Integrations::RateLimited
            raise
          rescue RenderApi::Error => error
            gaps << ResourceMap::Gap.new(text: Sentence.join("The custom domains of #{service['name']} could not be read", error), kinds: [ ResourceMap::KIND_DOMAIN ])
          end
        end
        [ [ POSTGRES, api.postgres_databases(account), "Postgres databases" ], [ KEY_VALUE, api.key_values(account), "Key Value instances" ] ].each do |type, stores, what|
          bounded(stores, what, [ ResourceMap::KIND_DATABASE ], gaps)
          stores.items.each { |store| reading.datastore(type, store) }
        end
        ResourceMap::Snapshot.new(resources: reading.resources, links: reading.links, gaps: gaps)
      end

      # A list read only up to its bound is a gap, and what it holds is not taken as gone.
      def bounded(read, what, kinds, gaps)
        gaps << ResourceMap::Gap.new(text: "Only the first #{read.items.size} #{what} were read.", kinds: kinds) if read.incomplete?
      end
      private :bounded

      # What normal looks like for its services and datastores: a week of CPU, memory and, for a datastore, active
      # connections, one reading an hour, instances added up. A resource Render cannot read keeps yesterday's baselines,
      # and being asked to slow down stops the whole read.
      def baselines_of(environment_row, resources, window)
        api = api(environment_row)
        resources.flat_map do |resource|
          type = type_of(resource)
          next [] unless type

          BASELINE_METRICS.filter_map do |name|
            metric = METRICS.fetch(name)
            next unless metric.applies.include?(type)

            series = api.metrics(metric.path, "resource" => resource.external_id, "startTime" => window.begin.utc.iso8601,
                                              "endTime" => window.end.utc.iso8601, "resolutionSeconds" => BASELINE_RESOLUTION)
            baseline(resource, name, series)
          end
        rescue Integrations::RateLimited
          raise
        rescue RenderApi::Error => error
          Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{error.message}")
          []
        end
      end

      def check_health!(environment_row)
        api(environment_row).owner(workspace_of(environment_row))
      rescue RenderApi::Error => error
        fail! error.message
      end

      # Builds the snapshot for map_of, one resource at a time.
      class MapReading
        attr_reader :resources, :links

        def initialize(account)
          @account = account
          @resources = []
          @links = []
        end

        def service(service, deploy)
          details = service["serviceDetails"] || {}
          commit = deploy&.dig("commit", "id")
          found = add(service["type"], service, status: service["suspended"] == SUSPENDED ? SUSPENDED : deploy&.dig("status"),
                                                details: {
                                                  "type" => TYPE_WORDS[service["type"]], "plan" => details["plan"], "region" => details["region"],
                                                  "instances" => details["numInstances"], "branch" => service["branch"],
                                                  ResourceMap::DEPLOYED_COMMIT => commit
                                                }.compact)
          repository(found, service["repo"])
          host = URI.parse(details["url"].to_s).host if details["url"].present?
          domain(found, host) if host.present?
          found
        rescue URI::InvalidURIError
          found
        end

        def datastore(type, store)
          add(type, store, status: store["status"],
                           details: { "type" => TYPE_WORDS[type], "plan" => store["plan"], "region" => store["region"],
                                      "engine" => ("Postgres #{store['version']}" if type == POSTGRES) }.compact)
        end

        def domain(service, host)
          found = ResourceMap.domain(host)
          @resources << found
          @links << ResourceMap::FoundLink.new(from: found.key, to: service, relation: ResourceMap::RELATION_SERVED_BY)
        end

        private

        def add(type, row, status:, details:)
          found = ResourceMap::Found.new(provider: PROVIDER_KEY, account: @account, kind: KINDS.fetch(type, ResourceMap::KIND_SERVICE),
                                         external_id: row["id"].to_s, name: row["name"].presence || row["id"].to_s, status: status,
                                         url: row["dashboardUrl"], details: details)
          @resources << found
          found.key
        end

        # The repository a service builds from, on whichever code host the registry knows.
        def repository(from, url)
          found = ResourceMap.repository_of(url)
          return unless found

          @resources << found
          @links << ResourceMap::FoundLink.new(from: from, to: found.key, relation: ResourceMap::RELATION_BUILT_FROM)
        end
      end

      private

      def api(environment_row)
        key = ConnectionSettings.of(environment_row).credential(API_KEY)
        fail! "This environment has no Render API key. Reconnect it on the Integrations page." if key.blank?

        RenderApi.new(key)
      end

      def workspace_of(environment_row) = ConnectionSettings.of(environment_row).field(WORKSPACE) || fail!("This environment has no Render workspace. Reconnect it.")

      def resources(environment_row)
        @resources ||= begin
          api = api(environment_row)
          workspace = workspace_of(environment_row)
          services = api.services(workspace).items.map do |service|
            { id: service["id"], name: service["name"], type: service["type"], url: service["dashboardUrl"],
              status: service["suspended"] == SUSPENDED ? "suspended by #{Array(service['suspenders']).join(', ').presence || 'Render'}" : "running" }
          end
          databases = api.postgres_databases(workspace).items.map do |database|
            { id: database["id"], name: database["name"], type: POSTGRES, url: database["dashboardUrl"], status: database["status"].to_s }
          end
          stores = api.key_values(workspace).items.map do |store|
            { id: store["id"], name: store["name"], type: KEY_VALUE, url: store["dashboardUrl"], status: store["status"].to_s }
          end
          services + databases + stores
        end
      end

      def find_resource(environment_row, asked)
        fail! "Say which service or datastore, by name or id. list_resources shows them." if asked.to_s.strip.empty?

        Named.find(resources(environment_row), asked, id: :id, name: :name, provider: PROVIDER, connection: environment_row) || fail!("Nothing called #{asked} in this workspace. list_resources shows what there is.")
      end

      # The page Render gives each resource (dashboardUrl), the only address its API returns.
      def link(resource) = resource[:url].present? ? Telemetry::Link.new(provider: PROVIDER, url: resource[:url]) : nil

      # The Render type of a map resource, from its kind and what the sweep wrote.
      def type_of(resource)
        return KEY_VALUE if resource.details.to_h["type"] == TYPE_WORDS[KEY_VALUE]
        return POSTGRES if resource.kind == ResourceMap::KIND_DATABASE

        TYPE_WORDS.key(resource.details.to_h["type"]) || (WEB_SERVICE if resource.kind == ResourceMap::KIND_SERVICE)
      end

      def chart(environment_row, resource, name, started, ended, resolution)
        metric = METRICS.fetch(name)
        query = { "resource" => resource[:id], "startTime" => started.utc.iso8601, "endTime" => ended.utc.iso8601,
                  "resolutionSeconds" => resolution }.merge(metric.query)
        series = api(environment_row).metrics(metric.path, query)
        series = status_class(series, STATUS_CLASSES[name]) if STATUS_CLASSES.key?(name)
        unit = series.filter_map { |each| each["unit"].presence }.first || "count"
        drawn = series.map do |each|
          Telemetry::Series.new(label: series_label(each, resource), points: points(each))
        end
        Telemetry::Chart.new(title: "#{metric.title} of #{resource[:name]}", unit: unit, series: drawn, from: started, to: ended, link: resource[:url])
      end

      # One series adding up every status code of the class, such as 500, 502 and 503 for 5xx.
      def status_class(series, digit)
        matching = series.select { |each| status_code(each).to_s.start_with?(digit) }
        summed = matching.flat_map { |each| points(each) }.group_by(&:first).map { |at, pairs| [ at, pairs.sum(&:last) ] }.sort_by(&:first)
        [ { "labels" => [ { "field" => "statusCode", "value" => "#{digit}xx" } ], "unit" => matching.first&.dig("unit"),
            "values" => summed.map { |at, value| { "timestamp" => at.utc.iso8601, "value" => value } } } ]
      end

      # The spec does not name the label a status code comes under, so it is the label whose value is one.
      def status_code(series) = Array(series["labels"]).map { |label| label["value"].to_s }.find { |value| value.match?(STATUS_CODE) }

      def series_label(series, resource)
        labels = Array(series["labels"]).reject { |label| [ "resource", "service" ].include?(label["field"]) }
        labels.map { |label| label["value"] }.compact.join(" ").presence || resource[:name]
      end

      def points(series)
        Array(series["values"]).filter_map do |point|
          at = Telemetry.parse_time(point["timestamp"])
          [ at, point["value"].to_f ] if at && !point["value"].nil?
        end
      end

      # Instances added up at each reading, so a service reads as a whole.
      def baseline(resource, name, series)
        readings = series.flat_map { |each| points(each) }.group_by(&:first).map { |at, pairs| [ at, pairs.sum(&:last) ] }.sort_by(&:first)
        return nil if readings.empty?

        unit = series.filter_map { |each| each["unit"].presence }.first
        ResourceMap::Baseline::Found.new(key: resource.key, metric: name, label: METRICS.fetch(name).title, unit: unit, points: readings)
      end

      def service_lines(environment_row, resource)
        service = api(environment_row).service(resource[:id])
        details = service["serviceDetails"] || {}
        autoscaling = details["autoscaling"] || {}
        commands = details["envSpecificDetails"] || {}
        latest = api(environment_row).deploys(resource[:id], limit: 1).first
        [
          "#{resource[:name]}, #{TYPE_WORDS.fetch(service['type'], service['type'])}, #{resource[:status]}",
          ([ ("plan #{details['plan']}" if details["plan"]), ("region #{details['region']}" if details["region"]),
             ("runtime #{details['runtime']}" if details["runtime"]) ].compact.join(", ").presence),
          scaling_line(details, autoscaling),
          ("Schedule: #{details['schedule']}, last succeeded #{details['lastSuccessfulRunAt'] || 'never'}" if details["schedule"]),
          source_line(service, commands),
          ("Address: #{details['url']}" if details["url"].present?),
          ("Health check path: #{details['healthCheckPath'].presence || 'none, so Render only checks that a port is open'}" if service["type"] == WEB_SERVICE),
          ("Disk: #{details.dig('disk', 'sizeGB')} GB at #{details.dig('disk', 'mountPath')}" if details["disk"]),
          ("Latest deploy: #{deploy_line(resource, latest)}" if latest),
          recent_events(environment_row, resource)
        ]
      end

      def scaling_line(details, autoscaling)
        if autoscaling["enabled"]
          criteria = %w[cpu memory].filter_map { |name| "#{name} #{autoscaling.dig('criteria', name, 'percentage')}%" if autoscaling.dig("criteria", name, "enabled") }
          return "Autoscaling between #{autoscaling['min']} and #{autoscaling['max']} instances on #{criteria.join(' and ').presence || 'no criteria'}"
        end
        "Instances: #{details['numInstances']}" if details.key?("numInstances")
      end

      def source_line(service, commands)
        what = service["repo"] ? "Runs #{service['repo']}#{", branch #{service['branch']}" if service['branch']}" : ("Runs the image #{service['imagePath']}" if service["imagePath"])
        start = commands["startCommand"] || commands["dockerCommand"]
        [ what, ("start command #{start}" if start.present?) ].compact.join(", ").presence
      end

      def recent_events(environment_row, resource)
        events = api(environment_row).events(resource[:id], "startTime" => EVENT_MINUTES.minutes.ago.utc.iso8601, "limit" => RECENT_EVENTS)
        return "Events in the last day: none" if events.empty?

        "Events in the last day, newest first:\n#{events.map { |event| event_line(event) }.join("\n")}"
      rescue Integrations::RateLimited
        raise
      rescue RenderApi::Error => error
        Sentence.join("Events could not be read", error)
      end

      def postgres_lines(environment_row, resource)
        database = api(environment_row).postgres(resource[:id])
        maintenance = database["maintenance"]
        [
          "#{resource[:name]}, Postgres #{database['version']}, status #{database['status']}",
          "Plan #{database['plan']}, region #{database['region']}, disk #{database['diskSizeGB'] || 'unknown'} GB" \
            "#{', grows on its own' if database['diskAutoscalingEnabled']}",
          "High availability #{database['highAvailabilityEnabled'] ? 'on' : 'off'}, role #{database['role']}, " \
            "#{Array(database['readReplicas']).size} read replicas, connection pooling #{database['connectionPool'] || 'none'}",
          ("Suspended by #{Array(database['suspenders']).join(', ')}" if database["suspended"] == SUSPENDED),
          ("Maintenance: #{maintenance['type']} #{maintenance['state']}, scheduled #{maintenance['scheduledAt']}" if maintenance)
        ]
      end

      def key_value_lines(environment_row, resource)
        store = api(environment_row).key_value(resource[:id])
        maintenance = store["maintenance"]
        [
          "#{resource[:name]}, Key Value #{store['version']}, status #{store['status']}",
          "Plan #{store['plan']}, region #{store['region']}",
          ("Eviction policy #{store.dig('options', 'maxmemoryPolicy')}, persistence #{store.dig('options', 'persistenceMode')}" if store["options"]),
          ("Maintenance: #{maintenance['type']} #{maintenance['state']}, scheduled #{maintenance['scheduledAt']}" if maintenance)
        ]
      end

      # A deploy's page, as Render's own CLI writes it (render-oss/cli, pkg/dashboard/dashboard.go).
      def deploy_line(resource, deploy)
        commit = deploy["commit"]
        what = if commit then "#{commit['id'].to_s.first(12)} \"#{commit['message'].to_s.lines.first.to_s.strip}\""
        elsif deploy["image"] then "image #{deploy.dig('image', 'ref')}"
        end
        page = "#{resource[:url]}/deploys/#{deploy['id']}" if resource[:url].present?
        [ deploy["createdAt"], "deploy #{deploy['id']}", deploy["status"], what, ("triggered by #{deploy['trigger'].to_s.tr('_', ' ')}" if deploy["trigger"]),
          ("finished #{deploy['finishedAt']}" if deploy["finishedAt"]), ("page #{page}" if page) ].compact.join(", ")
      end

      def event_line(event)
        details = event["details"] || {}
        said = [ details["deployStatus"], details["buildStatus"], details["status"].is_a?(String) ? details["status"] : nil,
                 ("from #{details['fromInstances']} to #{details['toInstances']} instances" if details.key?("toInstances")),
                 ("disk #{details['diskName']} at #{details['usagePercent']}%" if details["usagePercent"]),
                 failure_words(details["reason"].is_a?(Hash) && details["reason"].key?("failure") ? details.dig("reason", "failure") : details["reason"]),
                 details["message"] ].compact.join(", ")
        "#{event['timestamp']} #{event['type'].to_s.tr('_', ' ')}#{": #{said}" if said.present?}"
      end

      # Render's FailureReason (spec, schema failureReason) in words.
      def failure_words(reason)
        return nil unless reason.is_a?(Hash)

        [ ("ran out of memory, limit #{reason.dig('oomKilled', 'memoryLimit')}" if reason["oomKilled"]),
          ("exited with code #{reason['nonZeroExit']}" if reason["nonZeroExit"]),
          ("exited without being asked to stop" if reason["earlyExit"]),
          ("failed its health check: #{reason['unhealthy']}" if reason["unhealthy"].present?),
          ("timed out after #{reason['timedOutSeconds']} seconds#{": #{reason['timedOutReason']}" if reason['timedOutReason'].present?}" if reason["timedOutSeconds"]),
          ("evicted#{": #{reason['evictionReason']}" if reason['evictionReason'].present?}" if reason["evicted"]) ].compact.join(", ").presence
      end
    end
  end
end
