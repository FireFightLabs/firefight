module Integrations
  module Packs
    # Azure for the subscriptions an environment reads, one, several or every one its service principal can read (the
    # subscription connect field, a scope), with a service principal the workspace creates. It reads App Service and
    # Functions apps with their deployments and slots, Container Apps with their revisions, Azure SQL databases and
    # PostgreSQL flexible servers, their metrics from Azure Monitor and their logs from Log Analytics. Three tools change
    # something, each as Azure's own API does it, and only when the principal's roles allow it and the
    # tool is switched on: swapping a slot or moving a Container App's traffic, restarting, and scaling.
    #
    # Every endpoint, parameter and field is from the Resource Manager specifications in Azure/azure-rest-api-specs
    # (Microsoft.Web 2025-03-01, Microsoft.App 2025-01-01, Microsoft.Sql 2023-08-01, Microsoft.DBforPostgreSQL
    # 2024-08-01, Microsoft.Insights metrics 2023-10-01, Log Analytics query v1), and the log tables and columns are the
    # ones Azure Monitor's table reference gives.
    class Azure < NativePack
      # The environment row's credentials, which only this pack reads.
      TENANT = "tenant_id".freeze
      CLIENT = "client_id".freeze
      SECRET = "client_secret".freeze
      SUBSCRIPTION = "subscription_id".freeze

      PROVIDER = "Azure".freeze
      PROVIDER_KEY = "azure".freeze
      TYPE = "type".freeze
      TYPE_WEB = "App Service app".freeze
      TYPE_FUNCTION = "Function app".freeze
      TYPE_CONTAINER = "Container App".freeze
      TYPE_SQL = "Azure SQL database".freeze
      TYPE_POSTGRES = "PostgreSQL flexible server".freeze
      KINDS = {
        TYPE_WEB => ResourceMap::KIND_SERVICE, TYPE_FUNCTION => ResourceMap::KIND_SERVICE, TYPE_CONTAINER => ResourceMap::KIND_SERVICE,
        TYPE_SQL => ResourceMap::KIND_DATABASE, TYPE_POSTGRES => ResourceMap::KIND_DATABASE
      }.freeze
      # The kinds that serve hostnames, which go on the map with them.
      SERVES_HOSTS = [ TYPE_WEB, TYPE_FUNCTION, TYPE_CONTAINER ].freeze

      WEB_VERSION = "2025-03-01".freeze
      APP_VERSION = "2025-01-01".freeze
      SQL_VERSION = "2023-08-01".freeze
      POSTGRES_VERSION = "2024-08-01".freeze
      SQL_PORT = 1433
      POSTGRES_PORTS = [ 5432, 6432 ].freeze
      KEY_VAULT = "@Microsoft.KeyVault(".freeze
      # What a connection string's type says its value is for, as the parser names it.
      CONNECTION_SCHEMES = { "sqlazure" => "sqlserver", "sqlserver" => "sqlserver", "postgresql" => "postgresql", "mysql" => "mysql" }.freeze
      # Azure's clouds by the key of the region the connection was made in, the first being where one with none is.
      CLOUDS = { "global" => AzureApi::GLOBAL, "us_government" => AzureApi::US_GOVERNMENT, "china" => AzureApi::CHINA }.freeze
      PORTAL_PAGE = '%<portal>s/#@%<tenant>s/resource%<id>s/overview'.freeze

      STREAM_APP = Capabilities::STREAM_APP
      STREAM_REQUESTS = "requests".freeze
      STREAM_SYSTEM = "system".freeze
      STREAMS = [ STREAM_APP, STREAM_REQUESTS, STREAM_SYSTEM ].freeze
      # Where a Container App's environment sends its logs (appLogsConfiguration.destination).
      LOG_ANALYTICS = "log-analytics".freeze
      AZURE_MONITOR = "azure-monitor".freeze
      MULTIPLE = "Multiple".freeze
      FUNCTION_KIND = "functionapp".freeze
      MASTER = "master".freeze
      SCM_HOST = ".scm.".freeze
      # Plans that scale out on their own, where an instance count cannot be set.
      ELASTIC_TIERS = %w[Dynamic FlexConsumption ElasticPremium].freeze
      # Kudu's deployment states, as its DeployStatus names them.
      DEPLOY_STATES = { 0 => "pending", 1 => "building", 2 => "deploying", 3 => "failed", 4 => "succeeded" }.freeze
      HISTORY_STATES = {
        0 => Capabilities::History::QUEUED, 1 => Capabilities::History::RUNNING, 2 => Capabilities::History::RUNNING,
        3 => Capabilities::History::FAILED, 4 => Capabilities::History::SUCCEEDED
      }.freeze
      MISSING_TABLE = /resolve (?:table|scalar|column)/i

      LOG_LIMIT = 200
      # Cost Management's query (Query - Usage): the cost a bill shows, per day or per month, by the service that charged it.
      COST_GRANULARITIES = { Spend::BY_DAY => "Daily", Spend::BY_MONTH => "Monthly" }.freeze
      COST_DAYS = 30
      COST_DAYS_MAX = 365
      COST_MONTHS = 3
      COST_MONTHS_MAX = 12
      DEPLOY_LIMIT = 20
      LOG_TEXT_LIMIT = 2_000

      RESOURCE = { "type" => "string", "description" => "An App Service or Function app, Container App, Azure SQL database or PostgreSQL flexible server, by name or id, as list_resources shows it" }.freeze
      APP = { "type" => "string", "description" => "An App Service or Function app, or a Container App, by name or id, as list_resources shows it" }.freeze

      tool :list_resources,
           description: "The App Service and Function apps, Container Apps, Azure SQL databases and PostgreSQL flexible servers in " \
                        "the Azure subscription for this environment, with their resource group, region and state. Use it first " \
                        "to find the name to pass to the other tools",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :search_logs,
           description: "Log lines from one resource, newest first, at most #{LOG_LIMIT}, from Log Analytics. Filter by text, a " \
                        "regular expression, or text to leave out. stream app is what it prints, requests the HTTP requests an " \
                        "App Service app served, and system a Container App's platform events, such as failed starts. Azure " \
                        "keeps these only where a diagnostic setting sends them to a Log Analytics workspace",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "regex" => { "type" => "string", "description" => "Only lines matching this regular expression (optional)" },
               "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
               "stream" => { "type" => "string", "enum" => STREAMS, "description" => "Which logs: app, requests or system (optional, app)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :query_metrics,
           description: "Metrics of one resource over time, from Azure Monitor: requests, http_4xx, http_5xx, cpu, memory and " \
                        "network for an app, cpu_time for an App Service app, cpu, memory, disk and tcp_connections for a " \
                        "database. Returns min, average, max and latest, and the person sees each metric as a chart",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "metrics" => { "type" => "array", "items" => { "type" => "string", "enum" => Capabilities::METRIC_NAMES },
                              "description" => "Which metrics (optional, the resource's usual ones)" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :list_deployments,
           description: "What went out to an app, newest first. An App Service or Function app: its deployments (when, by whom, " \
                        "the message and whether it succeeded) and its deployment slots. A Container App: its revisions, with " \
                        "image, health, replicas and traffic share. Use it to see what changed before something broke, and for " \
                        "the slot or revision rollback_app takes",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => APP,
               "limit" => { "type" => "integer", "description" => "At most this many (optional, #{DEPLOY_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :describe_resource,
           description: "How one resource is set up and how it stands now: an app's state, plan or revision mode, image, " \
                        "instances or replicas and addresses, or a database's status, size and storage",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: true

      tool :rollback_app,
           description: "Put an app back on what ran before. An App Service or Function app swaps the named deployment slot with " \
                        "production, so what the slot runs goes live and production moves into the slot. Undo by swapping " \
                        "again. A Container App sends all its traffic to the named revision, which needs multiple revision " \
                        "mode. Undo by sending the traffic back. list_deployments shows the slots and revisions",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => APP,
               "to" => { "type" => "string", "description" => "The slot to swap with production, or the revision to serve all traffic, by name" }
             },
             "required" => %w[resource to]
           },
           read_only: false

      tool :restart_resource,
           description: "Restart an App Service or Function app, every active revision of a Container App, or a PostgreSQL " \
                        "flexible server, which drops its connections for a short while. Azure SQL databases have no restart",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: false

      tool :scale_app,
           description: "Set how many instances an app runs. An App Service app sets the instance count of its App Service plan, " \
                        "which every app on that plan shares. A Container App sets its fewest and most replicas. Undo by " \
                        "setting the values describe_resource showed before",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => APP,
               "instances" => { "type" => "integer", "description" => "How many instances: the plan's count, or a Container App's fewest replicas" },
               "min_replicas" => { "type" => "integer", "description" => "A Container App's fewest replicas, instead of instances (optional)" },
               "max_replicas" => { "type" => "integer", "description" => "A Container App's most replicas (optional)" }
             },
             "required" => [ "resource" ]
           },
           read_only: false

      tool :api_read,
           description: "Anything else Azure Resource Manager reads that the other tools do not cover, such as a Web App's " \
                        "deployment slots and deployments, a Container App's revisions and replicas, App Service plans, an AKS " \
                        "cluster's node pools, load balancers, Front Door and Application Gateway, Key Vault's settings, activity " \
                        "or a resource's health. A GET to a Resource Manager path inside this connection's subscription, as the " \
                        "API reference writes it, such as /subscriptions/<subscription>/resourceGroups/<group>/providers/" \
                        "Microsoft.Web/sites/<app>/slots, with api-version in query. A list answers one page, and its nextLink " \
                        "names the next. Only reads, so it never changes anything. Environment variables, keys and connection " \
                        "strings come back as their names. The azure_api skill says how to find a path",
           params_schema: ApiReads.path_schema("/subscriptions/<subscription>/resourceGroups/<group>/providers/Microsoft.App/containerApps/<app>/revisions"),
           read_only: true

      tool :cost_query,
           description: "What the Azure subscription spent, from Cost Management, by day or by month, with each period's total and the " \
                        "services that cost most. Use it to watch spend and find what grew and since when. Needs the Cost Management Reader role",
           params_schema: {
             "type" => "object",
             "properties" => {
               "by" => { "type" => "string", "enum" => COST_GRANULARITIES.keys, "description" => "day or month (optional, day)" },
               "days" => { "type" => "integer", "description" => "For by day, how many days back from today (optional, #{COST_DAYS}, at most #{COST_DAYS_MAX})" },
               "months" => { "type" => "integer", "description" => "For by month, how many months before this one (optional, #{COST_MONTHS}, at most #{COST_MONTHS_MAX})" }
             }
           },
           read_only: true

      def self.credential_fields
        [
          CredentialField.new(key: SECRET, label: "Client secret", secret: true, placeholder: "",
                              hint: "A client secret of the service principal's app registration. Give it Reader, Monitoring Reader and Log Analytics Reader " \
                                    "on each subscription it reads, and Cost Management Reader for Halon to watch spend. For Halon to apply fixes, add Website Contributor and Contributor on the apps it may change. " \
                                    "Optionally, to link App Service and Function apps to the databases their settings name, also give it a custom role " \
                                    "holding only Microsoft.Web/sites/config/list/action.")
        ]
      end

      # Reads each subscription chosen with the principal, or lists them for every one it can read, so a wrong secret or
      # subscription is said on the form before anything is saved. The tenant, client and subscriptions are connect
      # fields, whose format the registry already checked.
      def self.credential_refusal(values, region: nil, fields: {})
        secret = values[SECRET].to_s.strip
        tenant, client = fields.values_at(TENANT, CLIENT).map { |value| value.to_s.strip }
        subscriptions = Array(fields[SUBSCRIPTION]).map { |each| each.to_s.strip }.compact_blank
        return "Paste the client secret." if secret.empty?
        return "Enter the tenant and client id." if [ tenant, client ].any?(&:empty?)
        return "Choose at least one subscription, or all the service principal can read." if subscriptions.empty?

        if subscriptions == [ IntegrationProvider::ConnectField::ALL ]
          return "This service principal can read no Azure subscription. Give it Reader on one." if scope_options(values, region: region, fields: fields).empty?

          return nil
        end
        subscriptions.each do |subscription|
          AzureApi.new(tenant: tenant, client_id: client, client_secret: secret, subscription: subscription, cloud: cloud_of(region)).subscription_details
        rescue AzureApi::Error => error
          return Sentence.join("Azure refused this service principal or subscription #{subscription}", error)
        end
        nil
      rescue AzureApi::Error, NativePack::Error => error
        Sentence.join("Azure refused this service principal or subscription", error)
      end

      # The subscriptions the principal can read that are not disabled or deleted (Integrations::AzureApi#subscriptions),
      # each with its id and display name. whole refuses a list cut short, for a connection reading every subscription listed.
      def self.scope_options(values, region: nil, fields: {}, whole: false)
        secret = values.to_h.stringify_keys[SECRET].to_s.strip
        tenant, client = fields.to_h.stringify_keys.values_at(TENANT, CLIENT).map { |value| value.to_s.strip }
        raise NativePack::Error, "Paste the client secret, the tenant and the client id first." if [ secret, tenant, client ].any?(&:empty?)

        api = AzureApi.new(tenant: tenant, client_id: client, client_secret: secret, subscription: nil, cloud: cloud_of(region))
        read = api.subscriptions
        if whole && read.incomplete?
          raise NativePack::Error, "Azure lists more subscriptions than Firefight reads (the first #{read.items.size}). Choose the subscriptions instead of all."
        end

        read.items.reject { |subscription| UNREADABLE.include?(subscription["state"].to_s) }.map do |subscription|
          IntegrationProvider::ConnectOption.new(value: subscription["subscriptionId"].to_s,
                                                 label: subscription["displayName"].presence || subscription["subscriptionId"].to_s)
        end
      rescue AzureApi::Error => error
        raise NativePack::Error, Sentence.join("Azure did not list this service principal's subscriptions", error)
      end

      # A subscription in these states holds nothing to read (Subscription, SubscriptionState).
      UNREADABLE = %w[Disabled Deleted].freeze

      def self.scope_listing_capped? = true

      def self.cloud_of(region) = CLOUDS.fetch(region&.key.to_s, AzureApi::GLOBAL)

      # A new secret drops the tokens minted with the one before.
      def self.store_credentials!(environment_row, values)
        settings = ConnectionSettings.of(environment_row)
        settings.store_credential!(SECRET, values[SECRET].to_s.strip)
        settings.store_credential!(AzureApi::TOKEN_CACHE_KEY, nil)
      end

      def list_resources(environment_row:, arguments:)
        return every_subscription(environment_row) { |pack| pack.list_resources(environment_row: environment_row, arguments: arguments) } if every_scope?(environment_row)

        listing = catalog(environment_row)
        rows = listing.items.map { |item| "#{item[:name]} (#{item[:id]}), #{item[:type]} in #{item[:group]}, #{item[:location]}, #{item[:status]}" }
        gaps = listing.gaps.map { |gap| "Not listed: #{gap.text}" }
        subscription = subscription_of(environment_row)
        text = rows.empty? ? "Subscription #{subscription} has nothing Firefight reads." : "Subscription #{subscription}, #{rows.size} resources.\n#{rows.join("\n")}"
        Telemetry.result([ text, *gaps ].join("\n"), link: portal_link(environment_row, "/subscriptions/#{subscription}"))
      end

      def cost_query(environment_row:, arguments:)
        return every_subscription(environment_row) { |pack| pack.cost_query(environment_row: environment_row, arguments: arguments) } if every_scope?(environment_row)

        by = Spend.by(arguments)
        today = Time.current.utc.to_date
        started = Spend.since(arguments, days: COST_DAYS, days_most: COST_DAYS_MAX, months: COST_MONTHS, months_most: COST_MONTHS_MAX, today: today)
        body = {
          "type" => "ActualCost", "timeframe" => "Custom",
          "timePeriod" => { "from" => "#{started.iso8601}T00:00:00Z", "to" => "#{today.iso8601}T23:59:59Z" },
          "dataset" => { "granularity" => COST_GRANULARITIES.fetch(by), "aggregation" => { "totalCost" => { "name" => "Cost", "function" => "Sum" } },
                         "grouping" => [ { "type" => "Dimension", "name" => "ServiceName" } ] }
        }
        answer = api(environment_row).cost_query(body)
        subscription = subscription_of(environment_row)
        Telemetry.result("Subscription #{subscription}. #{cost_text(answer['properties'].to_h, by: by, started: started)}",
                         link: portal_link(environment_row, "/subscriptions/#{subscription}"))
      rescue AzureApi::Error => error
        fail! Sentence.join("Azure did not answer with the subscription's cost. The service principal needs the Cost Management Reader role", error)
      end

      def search_logs(environment_row:, arguments:)
        target = find(environment_row, arguments["resource"])
        stream = arguments["stream"].presence || STREAM_APP
        fail!("stream must be one of #{STREAMS.join(', ')}.") unless STREAMS.include?(stream)

        started, ended = Capabilities::Answers.range(arguments)
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        source = log_source(environment_row, target, stream)
        timespan = "#{started.utc.iso8601}/#{ended.utc.iso8601}"
        rows = nil
        source[:queries].each do |query|
          rows = read_logs(environment_row, source, "#{query}#{log_filters(arguments)} | order by TimeGenerated desc | take #{limit}", timespan)
          break
        rescue AzureApi::Error => error
          # A table the workspace does not have is passed over for the next place the logs may be.
          raise unless error.message.match?(MISSING_TABLE)
        end
        return Telemetry.result(not_kept(target, source), link: portal_link(environment_row, target.id)) if rows.nil?

        lines = rows.map { |row| Telemetry::LogLine.new(at: Telemetry.parse_time(row["TimeGenerated"]) || ended, source: row["Source"].to_s, text: row["Text"].to_s.truncate(LOG_TEXT_LIMIT)) }
        text = Telemetry.logs_text(lines, asked: "#{target.name} (#{stream}) from #{started.utc.iso8601} to #{ended.utc.iso8601}", limit: limit)
        text = "#{text}\n#{source[:note]}" if lines.empty?
        Telemetry.result(text, link: portal_link(environment_row, target.id))
      end

      def query_metrics(environment_row:, arguments:)
        target = find(environment_row, arguments["resource"])
        resource = read(environment_row, target)
        type = type_of(target, resource)
        known = Metrics::BY_TYPE.fetch(type)
        asked = Array(arguments["metrics"]).map(&:to_s).uniq
        unknown = asked - known.keys
        fail!("A #{type} has no #{unknown.join(', ')} in Azure Monitor. It has #{known.keys.join(', ')}.") if unknown.any?

        started, ended = Capabilities::Answers.range(arguments)
        minutes, grain = Metrics.grain(started, ended)
        link = portal_link(environment_row, target.id)
        charts = (asked.presence || Metrics::DEFAULTS.fetch(type)).map do |name|
          metric = known.fetch(name)
          points = read_metric(environment_row, metric, metric.on_plan ? resource.dig("properties", "serverFarmId") : target.id, started, ended, minutes, grain)
          Telemetry::Chart.new(title: "#{metric.title} of #{target.name}", unit: metric.unit, from: started, to: ended, link: link.url,
                               series: [ Telemetry::Series.new(label: target.name, points: points) ])
        end
        Telemetry.result("#{target.name}, a #{type}, every #{minutes} minutes\n#{Telemetry.charts_text(charts)}", link: link, charts: charts)
      end

      def list_deployments(environment_row:, arguments:)
        target = find(environment_row, arguments["resource"])
        limit = Capabilities::Answers.limit(arguments, DEPLOY_LIMIT)
        link = portal_link(environment_row, target.id)
        if target.site?
          text, runs = site_deployments(environment_row, target, limit)
          return Capabilities::RunHistory.with_runs(Telemetry.result(text, link: link), runs, link: link)
        end
        fail!("#{target.name} is a #{target.type}, which has no deployments. This works on an app.") unless target.container?

        Telemetry.result(container_revisions(environment_row, target, limit), link: link)
      end

      def describe_resource(environment_row:, arguments:)
        target = find(environment_row, arguments["resource"])
        resource = read(environment_row, target)
        lines = case target.type
        when TYPE_WEB then site_lines(environment_row, target, resource)
        when TYPE_CONTAINER then container_lines(resource)
        when TYPE_SQL then sql_lines(resource)
        when TYPE_POSTGRES then postgres_lines(resource)
        end
        Telemetry.result(lines.compact.join("\n"), link: portal_link(environment_row, target.id))
      end

      def rollback_app(environment_row:, arguments:)
        target = find(environment_row, arguments["resource"])
        to = arguments["to"].to_s.strip
        fail!("Say what to go back to: a slot of an App Service app, or a revision of a Container App, as list_deployments shows them.") if to.empty?

        text = if target.site? then swap_slot(environment_row, target, to)
        elsif target.container? then move_traffic(environment_row, target, to)
        else fail!("#{target.name} is a #{target.type}, which cannot be rolled back here. Restore it from a backup in the portal.")
        end
        Telemetry.result(text, link: portal_link(environment_row, target.id))
      end

      def restart_resource(environment_row:, arguments:)
        target = find(environment_row, arguments["resource"])
        api = api(environment_row)
        text = case target.type
        when TYPE_WEB
          api.post("#{target.id}/restart", WEB_VERSION)
          "Azure is restarting #{target.name}."
        when TYPE_CONTAINER
          active = revisions(environment_row, target).select { |revision| revision.dig("properties", "active") }
          fail!("#{target.name} has no active revision to restart.") if active.empty?

          active.each { |revision| api.post("#{target.id}/revisions/#{api.segment(revision['name'])}/restart", APP_VERSION) }
          "Azure is restarting #{target.name}'s active #{'revision'.pluralize(active.size)} #{active.map { |revision| revision['name'] }.join(', ')}."
        when TYPE_POSTGRES
          api.post("#{target.id}/restart", POSTGRES_VERSION)
          "Azure is restarting PostgreSQL flexible server #{target.name}. Its connections drop until it is back, usually within a few minutes."
        else
          fail!("Azure SQL has no restart for a database. For one stuck in a bad state, look at its blocking and long running queries first.")
        end
        Telemetry.result("#{text} There is nothing to undo.", link: portal_link(environment_row, target.id))
      end

      def scale_app(environment_row:, arguments:)
        target = find(environment_row, arguments["resource"])
        text = if target.site? then scale_plan(environment_row, target, arguments)
        elsif target.container? then scale_replicas(environment_row, target, arguments)
        else fail!("#{target.name} is a #{target.type}. Its size is changed in the portal, since a database's tier is not an instance count.")
        end
        Telemetry.result(text, link: portal_link(environment_row, target.id))
      end

      # A GET the read guard let through (ReadGuards::Azure), in a subscription the connection reads, answering with the
      # portal page of the resource the path reads in.
      def api_read(environment_row:, arguments:)
        call = begin
          ReadGuards::Azure.reading(ApiReads::TOOL, arguments)
        rescue ReadGuards::Refused => error
          fail!(error.message)
        end
        path, query = call.values_at("path", "query")
        settings = ConnectionSettings.of(environment_row)
        subscription = ReadGuards::Azure.subscription_in(path)
        outside = ApiReads.outside_scopes(settings, [ subscription ], "subscriptions")
        fail_policy!(outside) if outside

        reading = scoped(subscription || @scope || settings.known_scopes.first)
        answer = reading.send(:api, environment_row).get(path, query[ReadGuards::Azure::API_VERSION], query.except(ReadGuards::Azure::API_VERSION))
        text = ApiReads.answer(PROVIDER, ApiReads.asked(path, query), ReadGuards::Azure.hidden(answer))
        Telemetry.result(text, link: (portal_link(environment_row, resource_of(path)) if subscription))
      end

      # The resource a Resource Manager path reads in, its subscription, resource group, or the resource a provider names
      # under it, which is what the portal opens a page for.
      def resource_of(path)
        segments = path.delete_prefix("/").split("/")
        provider = segments.index("providers")
        kept = provider && segments.size >= provider + 4 ? provider + 4 : [ provider || segments.size, 4 ].min
        "/#{segments.first(kept).join('/')}"
      end
      private :resource_of

      # Reads each subscription the connection reaches, so one the principal can no longer read is said on the connection.
      def check_health!(environment_row)
        ConnectionSettings.of(environment_row).scopes.each { |subscription| scoped(subscription).send(:api, environment_row).subscription_details }
      rescue AzureApi::Error => error
        fail! error.message
      end

      # The subscription on the resource map: its App Service and Function apps and Container Apps with the hostnames they
      # serve, its Azure SQL databases and PostgreSQL flexible servers. A list the principal may not read is a gap, and
      # nothing of its kind is taken as gone. Each app's settings are read in memory and each database reports the
      # address it is reached at, so the map links an app to the database its settings name.
      def map_of(environment_row)
        map_of_scopes(environment_row, kinds: MAP_KINDS) { |pack| pack.map_of_subscription(environment_row) }
      end

      # What a sweep puts on the map for one subscription.
      MAP_KINDS = [ *KINDS.values.uniq, ResourceMap::KIND_DOMAIN ].freeze

      def map_of_subscription(environment_row)
        subscription = subscription_of(environment_row)
        listing = catalog(environment_row)
        reading = MapReading.new(SettingsReading.new(workspace: environment_row.integration.workspace, gaps: [], stopped: []))
        listing.items.each { |item| map_item(environment_row, subscription, item, reading) }
        reading.snapshot(listing.gaps)
      end

      # Only the app or database an activity log event named, read again as the sweep reads it, with the hostnames it
      # serves, an app's settings and a database's address. Gone only when Resource Manager answers not found for it. nil
      # for a scope Azure cannot narrow to.
      def map_refresh(environment_row, scope)
        target = Target.parse(scope.external_id)
        if every_scope?(environment_row)
          reached = ConnectionSettings.of(environment_row).scopes.find { |each| target && each.casecmp?(target.subscription) }
          return reached && scoped(reached).map_refresh(environment_row, scope)
        end
        subscription = subscription_of(environment_row)
        return unless target && target.subscription.casecmp?(subscription) && target.name != MASTER

        item = begin
          refreshed_item(api(environment_row), target)
        rescue AzureApi::NotFound
          return ResourceMap::Snapshot.new(resources: [], gone: [ [ PROVIDER_KEY, subscription, KINDS.fetch(target.type), target.id ] ])
        end
        reading = MapReading.new(SettingsReading.new(workspace: environment_row.integration.workspace, gaps: [], stopped: []))
        map_item(environment_row, subscription, item, reading)
        reading.snapshot([])
      end

      # What map_of and map_refresh read, one app or database at a time.
      MapReading = Struct.new(:settings, :resources, :links, :uses, :endpoints) do
        def initialize(settings) = super(settings, [], [], [], [])

        def snapshot(gaps) = ResourceMap::Snapshot.new(resources: resources, links: links, gaps: gaps + settings.gaps, uses: uses, endpoints: endpoints)
      end

      # What normal looks like for each app and database, read an hour at a time over the window. A resource Azure will
      # not read keeps yesterday's baselines, and being asked to slow down stops the whole read.
      def baselines_of(environment_row, resources, window)
        return by_scope(environment_row, resources) { |pack, group| pack.baselines_of(environment_row, group, window) } unless scope

        resources.flat_map do |resource|
          target = Target.parse(resource.external_id)
          type = resource.details.to_h[TYPE]
          next [] unless target && Metrics::BASELINES.key?(type)

          site = read(environment_row, target) if target.site?
          Metrics::BASELINES.fetch(type).filter_map do |name|
            metric = Metrics::BY_TYPE.fetch(type).fetch(name)
            scope = metric.on_plan ? site&.dig("properties", "serverFarmId") : target.id
            points = read_metric(environment_row, metric, scope, window.begin, window.end, 60, Metrics::GRAINS.fetch(60))
            ResourceMap::Baseline::Found.new(key: resource.key, metric: name, label: metric.title, unit: metric.unit, points: points) if points.any?
          end
        rescue Integrations::RateLimited
          raise
        rescue AzureApi::Error => error
          Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{error.message}")
          []
        end
      end

      Listing = Data.define(:items, :gaps)
      # What one map read needs to turn settings into uses, what it could not read, and whether it stopped reading app
      # settings (after Azure refused them or asked to slow down).
      SettingsReading = Data.define(:workspace, :gaps, :stopped)

      private

      def api(environment_row)
        settings = ConnectionSettings.of(environment_row)
        tenant, client, subscription = settings.field(TENANT), settings.field(CLIENT), subscription_of(environment_row)
        secret = settings.credential(SECRET)
        fail! "This environment has no Azure service principal. Reconnect it on the Integrations page." if [ tenant, client, secret, subscription ].any?(&:blank?)

        @api ||= AzureApi.new(tenant: tenant, client_id: client, client_secret: secret, subscription: subscription,
                              cloud: self.class.cloud_of(settings.region), token_cache: settings)
      end

      def subscription_of(environment_row) = scope!(environment_row)

      # A listing of every subscription the connection reaches, each read by a pack of its own.
      def every_subscription(environment_row)
        texts = ConnectionSettings.of(environment_row).scopes.map do |subscription|
          Array(yield(scoped(subscription))["content"]).filter_map { |part| part["text"] }.join("\n")
        end
        Telemetry.result(texts.join("\n\n"), link: nil)
      end

      def catalog(environment_row)
        @catalog ||= begin
          api = api(environment_row)
          root = "/subscriptions/#{api.segment(subscription_of(environment_row))}/providers"
          items = []
          gaps = []
          {
            "App Service and Function apps" => [ [ TYPE_WEB, TYPE_FUNCTION ], -> { whole(api.list("#{root}/Microsoft.Web/sites", WEB_VERSION)) { |site| site_item(site) } } ],
            "Container Apps" => [ [ TYPE_CONTAINER ], -> { whole(api.list("#{root}/Microsoft.App/containerApps", APP_VERSION)) { |app| container_item(app) } } ],
            "Azure SQL databases" => [ [ TYPE_SQL ], -> { sql_items(api, root) } ],
            "PostgreSQL flexible servers" => [ [ TYPE_POSTGRES ], -> { whole(api.list("#{root}/Microsoft.DBforPostgreSQL/flexibleServers", POSTGRES_VERSION)) { |server| postgres_item(server) } } ]
          }.each do |what, (types, read)|
            found, complete = read.call
            items.concat(found)
            next if complete

            gaps << ResourceMap::Gap.new(text: "Only the first #{found.size} #{what} were read.", kinds: listed_kinds(types))
          rescue Integrations::RateLimited
            raise
          rescue AzureApi::Error => error
            gaps << ResourceMap::Gap.new(text: Sentence.join("#{what} could not be read", error), kinds: listed_kinds(types))
          end
          Listing.new(items: items, gaps: gaps)
        end
      end

      # One app or database onto the reading, with the hostnames it serves, and an app's settings or a database's address.
      def map_item(environment_row, subscription, item, reading)
        found = ResourceMap::Found.new(provider: PROVIDER_KEY, account: subscription, kind: KINDS.fetch(item[:type]), external_id: item[:id], name: item[:name],
                                       status: item[:status], url: portal_link(environment_row, item[:id]).url, details: item[:details])
        reading.resources << found
        item[:hosts].each do |host|
          domain = ResourceMap.domain(host)
          reading.resources << domain
          reading.links << ResourceMap::FoundLink.new(from: domain.key, to: found.key, relation: ResourceMap::RELATION_SERVED_BY)
        end
        case item[:type]
        when TYPE_WEB, TYPE_FUNCTION then reading.uses.concat(site_settings(environment_row, found.key, item, reading.settings))
        when TYPE_CONTAINER then reading.uses.concat(container_settings(found.key, item[:source], reading.settings))
        when TYPE_SQL, TYPE_POSTGRES then reading.endpoints.concat(database_endpoints(found.key, item, reading.settings))
        end
      end

      # One app or database read as the list reads it. An Azure SQL database's address is its server's.
      def refreshed_item(api, target)
        case target.type
        when TYPE_WEB then site_item(api.get(target.id, WEB_VERSION))
        when TYPE_CONTAINER then container_item(api.get(target.id, APP_VERSION))
        when TYPE_POSTGRES then postgres_item(api.get(target.id, POSTGRES_VERSION))
        when TYPE_SQL then sql_item(api.get(target.id.sub(%r{/databases/[^/]+\z}i, ""), SQL_VERSION), api.get(target.id, SQL_VERSION))
        end
      end

      # What a list puts on the map. Apps also put the hostnames they serve there.
      def listed_kinds(types) = [ *types.map { |type| KINDS.fetch(type) }, (ResourceMap::KIND_DOMAIN if types.intersect?(SERVES_HOSTS)) ].compact.uniq

      def item(resource, type, status, hosts: [], details: {})
        target = Target.parse(resource["id"])
        { type: type, id: resource["id"], name: resource["name"], group: target&.group, location: resource["location"], status: status.to_s.downcase.presence || "unknown",
          hosts: hosts, details: { TYPE => type, "resource_group" => target&.group, "region" => resource["location"],
                                   ResourceMap::TAGS => resource["tags"].presence }.merge(details).compact }
      end

      def site_item(site)
        properties = site["properties"].to_h
        hosts = Array(properties["enabledHostNames"]).reject { |host| host.include?(SCM_HOST) }
        item(site, function?(site) ? TYPE_FUNCTION : TYPE_WEB, properties["state"], hosts: hosts,
             details: { "plan" => properties["serverFarmId"].to_s.split("/").last.presence, "sku" => properties["sku"] })
      end

      def container_item(app)
        properties = app["properties"].to_h
        ingress = properties.dig("configuration", "ingress").to_h
        hosts = [ ingress["fqdn"], *Array(ingress["customDomains"]).filter_map { |domain| domain["name"] } ].compact
        item(app, TYPE_CONTAINER, properties["runningStatus"] || properties["provisioningState"], hosts: hosts,
             details: { "revision_mode" => properties.dig("configuration", "activeRevisionsMode"), "latest_revision" => properties["latestReadyRevisionName"] })
          .merge(source: app)
      end

      # An App Service or Function app's settings and connection strings, read in memory through the two list actions
      # (https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/list-application-settings and
      # /list-connection-strings). Both need Microsoft.Web/sites/config/list/action, which Reader does not hold, so the
      # first refusal is one gap and the rest of the apps are not asked. A Key Vault reference is named only
      # (https://learn.microsoft.com/en-us/azure/app-service/app-service-key-vault-references). A connection string's type
      # says what its value is for, such as SQLAzure or PostgreSQL.
      def site_settings(environment_row, key, item, reading)
        return [] if reading.stopped.any?

        settings = api(environment_row).post("#{item[:id]}/config/appsettings/list", WEB_VERSION).dig("properties").to_h
        strings = api(environment_row).post("#{item[:id]}/config/connectionstrings/list", WEB_VERSION).dig("properties").to_h
        vault, values = settings.partition { |_, value| value.to_s.start_with?(KEY_VAULT) }
        uses = ResourceMap::Use.read(from: key, workspace: reading.workspace, values: values.to_h, names: vault.map(&:first))
        uses + strings.filter_map do |name, string|
          value = string.to_h["value"].to_s
          next ResourceMap::Use.named(key, name) if value.start_with?(KEY_VAULT)

          ResourceMap::Use.of(key, name, value, reading.workspace, scheme: CONNECTION_SCHEMES[string.to_h["type"].to_s.downcase])
        end
      rescue Integrations::RateLimited => error
        reading.stopped << error
        reading.gaps << ResourceMap::Gap.new(text: Sentence.join("Azure asked to slow down while reading app settings, so the rest were not read", error), kinds: [], settings: true)
        []
      rescue AzureApi::Forbidden => error
        reading.stopped << error
        reading.gaps << ResourceMap::Gap.new(text: Sentence.join("App settings could not be read. Reading them needs Microsoft.Web/sites/config/list/action, " \
                                                                 "which the Reader role does not include. A custom role holding only that action is optional, and links " \
                                                                 "App Service and Function apps to the databases their settings name", error), kinds: [], settings: true)
        []
      rescue AzureApi::Error => error
        reading.gaps << ResourceMap::Gap.new(text: Sentence.join("The settings of #{item[:name]} could not be read", error), kinds: [], settings: true)
        []
      end

      # A Container App's variables are in the app it lists (Container.env, each a value or a secretRef,
      # https://learn.microsoft.com/en-us/rest/api/resource-manager/containerapps/container-apps/get). A secret is named
      # only, and its value is never asked for.
      def container_settings(key, app, reading)
        env = Array(app.dig("properties", "template", "containers")).flat_map { |container| Array(container["env"]) }
        values, secrets = env.partition { |variable| variable.key?("value") }
        ResourceMap::Use.read(from: key, workspace: reading.workspace, values: values.to_h { |variable| [ variable["name"].to_s, variable["value"].to_s ] },
                              names: secrets.map { |variable| variable["name"] })
      end

      # A database's server name (fullyQualifiedDomainName on an Azure SQL server and a PostgreSQL flexible server). An
      # Azure SQL server holds several databases, so each is told apart by its name. A flexible server also answers
      # through PgBouncer on 6432 when it is on (https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-pgbouncer).
      def database_endpoints(key, item, reading)
        host = item[:server_host]
        found = if item[:type] == TYPE_SQL
          [ ResourceMap::Endpoint.at(resource: key, host: host, port: SQL_PORT, workspace: reading.workspace, database: item[:name]) ]
        else
          POSTGRES_PORTS.map { |port| ResourceMap::Endpoint.at(resource: key, host: host, port: port, workspace: reading.workspace) }
        end
        found.compact
      end

      # A list's resources as items, and whether the list was read in full.
      def whole(read, &) = [ read.items.map(&), read.complete ]

      def sql_items(api, root)
        servers = api.list("#{root}/Microsoft.Sql/servers", SQL_VERSION)
        complete = servers.complete
        found = servers.items.flat_map do |server|
          databases = api.list("#{server['id']}/databases", SQL_VERSION)
          complete &&= databases.complete
          databases.items.reject { |database| database["name"] == MASTER }.map { |database| sql_item(server, database) }
        end
        [ found, complete ]
      end

      def sql_item(server, database)
        item(database, TYPE_SQL, database.dig("properties", "status"),
             details: { "server" => server["name"], "sku" => database.dig("sku", "name"), "objective" => database.dig("properties", "currentServiceObjectiveName") })
          .merge(server_host: server.dig("properties", "fullyQualifiedDomainName"))
      end

      def postgres_item(server)
        properties = server["properties"].to_h
        item(server, TYPE_POSTGRES, properties["state"],
             details: { "version" => properties["version"], "sku" => server.dig("sku", "name"), "storage_gb" => properties.dig("storage", "storageSizeGB") })
          .merge(server_host: properties["fullyQualifiedDomainName"])
      end

      def function?(site) = site["kind"].to_s.split(",").map(&:strip).include?(FUNCTION_KIND)

      # A resource by its id, or by its name from the map's last sweep and then the subscription's live list. Only the
      # connected subscription is reached, whatever id is given.
      def find(environment_row, asked)
        wanted = asked.to_s.strip
        fail! "Say which resource, by name or id. list_resources shows them." if wanted.empty?

        target = Target.parse(wanted) || named(environment_row, wanted)
        fail!("Nothing called #{wanted} in this subscription. list_resources shows what there is.") unless target
        unless target.subscription.casecmp?(subscription_of(environment_row))
          fail!("#{wanted} is in subscription #{target.subscription}, and this connection reaches #{subscription_of(environment_row)}.")
        end

        target
      end

      # By its name on the map's last sweep, then in the live list. A name two resources share is refused with their ids.
      def named(environment_row, wanted)
        mapped = ResourceMap::Resource.present.where(integration_environment: environment_row, account: subscription_of(environment_row)).pluck(:external_id, :name).map { |id, name| { id: id, name: name } }
        found = Named.find(mapped, wanted, id: :id, name: :name, provider: PROVIDER, connection: environment_row) ||
                Named.find(catalog(environment_row).items, wanted, id: :id, name: :name, provider: PROVIDER, connection: environment_row)
        found && Target.parse(found[:id])
      end

      def read(environment_row, target)
        version = { TYPE_WEB => WEB_VERSION, TYPE_CONTAINER => APP_VERSION, TYPE_SQL => SQL_VERSION, TYPE_POSTGRES => POSTGRES_VERSION }.fetch(target.type)
        (@read ||= {})[target.id] ||= api(environment_row).get(target.id, version)
      end

      def type_of(target, resource) = target.site? && function?(resource) ? TYPE_FUNCTION : target.type

      def revisions(environment_row, target) = api(environment_row).list("#{target.id}/revisions", APP_VERSION).items

      def count(value, name)
        return nil if value.nil? || value.to_s.strip.empty?

        number = Integer(value, exception: false)
        fail!("#{name} must be a whole number, 0 or more.") unless number && number >= 0
        number
      end

      # Where a resource's logs are and the Kusto queries that read them, each projecting TimeGenerated, Source and Text,
      # tried in order. The tables and columns are the ones Azure Monitor's table reference gives.
      def log_source(environment_row, target, stream)
        if target.container?
          container_log_source(environment_row, target, stream)
        else
          fail!("Only a Container App has system logs here. Ask for stream #{STREAM_APP}.") if stream == STREAM_SYSTEM
          site_or_database_source(environment_row, target, stream)
        end
      end

      def site_or_database_source(environment_row, target, stream)
        if stream == STREAM_REQUESTS
          fail!("Only an App Service or Function app keeps request logs here. Ask for stream #{STREAM_APP}.") unless target.site?

          return resource_source(target, [ "AppServiceHTTPLogs | project TimeGenerated, Source = CIp, " \
                                           "Text = strcat(CsMethod, \" \", CsUriStem, \" \", tostring(ScStatus), \" \", tostring(TimeTaken), \"ms\")" ],
                                 "AppServiceHTTPLogs")
        end

        case target.type
        when TYPE_WEB
          if function?(read(environment_row, target))
            resource_source(target, [ "FunctionAppLogs | project TimeGenerated, Source = strcat(FunctionName, \" \", Level), Text = Message" ], "FunctionAppLogs")
          else
            resource_source(target, [ "AppServiceConsoleLogs | project TimeGenerated, Source = strcat(Host, \" \", Level), Text = ResultDescription" ], "AppServiceConsoleLogs")
          end
        when TYPE_POSTGRES
          resource_source(target, [ "PGSQLServerLogs | project TimeGenerated, Source = ErrorLevel, Text = Message",
                                    "AzureDiagnostics | where Category == \"PostgreSQLLogs\" | project TimeGenerated, Source = column_ifexists(\"errorLevel_s\", \"\"), Text = column_ifexists(\"Message\", \"\")" ],
                          "PostgreSQLLogs")
        when TYPE_SQL
          resource_source(target, [ "AzureDiagnostics | where Category in (\"Errors\", \"Timeouts\", \"Blocks\", \"Deadlocks\") | project TimeGenerated, Source = Category, " \
                                    "Text = iff(isempty(column_ifexists(\"Message\", \"\")), tostring(pack_all(true)), column_ifexists(\"Message\", \"\"))" ],
                          "Errors, Timeouts, Blocks and Deadlocks")
        end
      end

      def resource_source(target, queries, what)
        { scope: :resource, id: target.id, queries: queries, what: what,
          note: "Log Analytics keeps #{what} for #{target.name} only when a diagnostic setting on it sends them to a workspace, so no lines can also mean none is set." }
      end

      # A Container App's logs are kept by its environment, in the environment's Log Analytics workspace or in Azure
      # Monitor tables a diagnostic setting on the environment writes, whichever the environment is set to.
      def container_log_source(environment_row, target, stream)
        fail!("Only an App Service or Function app keeps request logs here. Ask for stream #{STREAM_APP} or #{STREAM_SYSTEM}.") if stream == STREAM_REQUESTS

        app = read(environment_row, target)
        environment_id = app.dig("properties", "managedEnvironmentId") || app.dig("properties", "environmentId")
        environment = api(environment_row).get(environment_id, APP_VERSION)
        logs = environment.dig("properties", "appLogsConfiguration").to_h
        system = stream == STREAM_SYSTEM
        case logs["destination"]
        when LOG_ANALYTICS
          table = system ? "ContainerAppSystemLogs_CL" : "ContainerAppConsoleLogs_CL"
          { scope: :workspace, id: logs.dig("logAnalyticsConfiguration", "customerId"), what: table,
            queries: [ "#{table} | where ContainerAppName_s == #{kusto(target.name)} | project TimeGenerated, Source = column_ifexists(\"RevisionName_s\", \"\"), Text = Log_s" ],
            note: "Log Analytics takes a few minutes to receive a Container App's lines." }
        when AZURE_MONITOR
          table = system ? "ContainerAppSystemLogs" : "ContainerAppConsoleLogs"
          { scope: :resource, id: environment_id, what: table,
            queries: [ "#{table} | where ContainerAppName == #{kusto(target.name)} | project TimeGenerated, Source = RevisionName, Text = Log" ],
            note: "These are kept only when a diagnostic setting on the Container Apps environment sends #{table} to a workspace." }
        else
          fail!("#{target.name}'s environment keeps no logs, since its log destination is #{logs['destination'].presence || 'none'}. " \
                "Set one in the portal, under the environment's Logging options.")
        end
      end

      def read_logs(environment_row, source, query, timespan)
        api = api(environment_row)
        answer = source[:scope] == :workspace ? api.query_workspace_logs(source[:id], query, timespan) : api.query_resource_logs(source[:id], query, timespan)
        table = Array(answer["tables"]).first.to_h
        columns = Array(table["columns"]).map { |column| column["name"] }
        Array(table["rows"]).map { |row| columns.zip(row).to_h }
      end

      def log_filters(arguments)
        [
          (" | where Text contains #{kusto(arguments['text'])}" if arguments["text"].present?),
          (" | where Text matches regex #{kusto(arguments['regex'])}" if arguments["regex"].present?),
          (" | where Text !contains #{kusto(arguments['exclude'])}" if arguments["exclude"].present?)
        ].compact.join
      end

      # A string in Kusto, quoted and escaped, so a value never becomes part of the query.
      def kusto(value) = "\"#{value.to_s.gsub('\\') { '\\\\' }.gsub('"') { '\\"' }.gsub("\n") { '\\n' }.gsub("\r") { '\\r' }}\""

      def not_kept(target, source)
        "Log Analytics has no #{source[:what]} for #{target.name}, so no diagnostic setting sends them to a workspace yet. " \
          "The connection works. In the portal, open #{target.name}, then Diagnostic settings, and send #{source[:what]} to a Log Analytics workspace. " \
          "Until then, read its metrics."
      end

      # One metric's readings, as rates where the metric is a count, so a reading reads the same whatever the grain.
      def read_metric(environment_row, metric, resource_id, started, ended, minutes, grain)
        return [] if resource_id.blank?

        query = { "timespan" => "#{started.utc.iso8601}/#{ended.utc.iso8601}", "interval" => grain, "metricnames" => metric.name,
                  "aggregation" => metric.aggregation, "$filter" => ("#{Metrics::STATUS_DIMENSION} eq '*'" if metric.status) }
        answer = api(environment_row).metrics(resource_id, query)
        series = Array(answer.dig("value", 0, "timeseries"))
        series = series.select { |each| status_of(each).start_with?(metric.status) } if metric.status
        divisor = { minute: minutes, second: minutes * 60 }.fetch(metric.rate, 1)
        series.flat_map { |each| Array(each["data"]) }.group_by { |point| point["timeStamp"] }.filter_map do |stamp, points|
          values = points.filter_map { |point| point[metric.aggregation] }
          at = Telemetry.parse_time(stamp)
          [ at, values.sum.to_f * metric.scale / divisor ] if at && values.any?
        end.sort_by(&:first)
      end

      def status_of(series)
        Array(series["metadatavalues"]).find { |value| value.dig("name", "value").to_s.casecmp?(Metrics::STATUS_DIMENSION) }&.dig("value").to_s
      end

      def site_deployments(environment_row, target, limit)
        api = api(environment_row)
        deployments = api.list("#{target.id}/deployments", WEB_VERSION).items.sort_by { |deployment| deployment.dig("properties", "start_time").to_s }.reverse.first(limit)
        slots = api.list("#{target.id}/slots", WEB_VERSION).items.map { |slot| "#{slot['name'].to_s.split('/').last} (#{slot.dig('properties', 'state').to_s.downcase})" }
        rows = deployments.map do |deployment|
          properties = deployment["properties"].to_h
          [ properties["start_time"], DEPLOY_STATES.fetch(properties["status"], "status #{properties['status']}"), ("active" if properties["active"]),
            ("by #{properties['author'].presence || properties['deployer']}" if properties["author"].present? || properties["deployer"].present?),
            ("\"#{properties['message'].to_s.lines.first.to_s.strip}\"" if properties["message"].present?), "deployment #{deployment['name']}" ].compact.join(", ")
        end
        text = [ rows.any? ? "Latest #{rows.size} deployments of #{target.name}, newest first.\n#{rows.join("\n")}" : "#{target.name} has no deployments recorded.",
                 slots.any? ? "Deployment slots, which rollback_app swaps with production: #{slots.join(', ')}." : "It has no deployment slots, so it cannot be rolled back by a swap." ].join("\n")
        [ text, deployments.map { |deployment| history_run(deployment) } ]
      end

      # A deployment as every run history reads it, from the start_time, end_time and status App Service's Deployment
      # resource keeps (Web Apps, List Deployments).
      def history_run(deployment)
        properties = deployment["properties"].to_h
        Capabilities::History::Run.new(
          id: deployment["name"].to_s.split("/").last, name: "deploy", status: HISTORY_STATES.fetch(properties["status"], Capabilities::History::RUNNING),
          started_at: Capabilities::RunHistory.time(properties["start_time"]), finished_at: Capabilities::RunHistory.time(properties["end_time"]),
          detail: properties["message"].to_s.lines.first.to_s.strip.truncate(120).presence
        )
      end

      def container_revisions(environment_row, target, limit)
        app = read(environment_row, target)
        traffic = app.dig("properties", "configuration", "ingress", "traffic").to_a
        rows = revisions(environment_row, target).sort_by { |revision| revision.dig("properties", "createdTime").to_s }.reverse.first(limit).map do |revision|
          properties = revision["properties"].to_h
          image = Array(properties.dig("template", "containers")).filter_map { |container| container["image"] }.join(", ")
          [ properties["createdTime"], revision["name"], (properties["active"] ? "active" : "inactive"), "health #{properties['healthState'].to_s.downcase}",
            "running #{properties['runningState'].to_s.downcase}", "#{properties['replicas'].to_i} replicas", "#{properties['trafficWeight'].to_i}% of traffic",
            "image #{image}" ].join(", ")
        end
        mode = app.dig("properties", "configuration", "activeRevisionsMode")
        return "#{target.name} has no revisions." if rows.empty?

        "Latest #{rows.size} revisions of #{target.name}, newest first, in #{mode.to_s.downcase} revision mode#{" with traffic split #{traffic_text(traffic)}" if traffic.any?}. " \
          "rollback_app takes a revision's name#{', which needs multiple revision mode' unless mode == MULTIPLE}.\n#{rows.join("\n")}"
      end

      def traffic_text(traffic)
        traffic.map { |weight| "#{weight['weight']}% to #{weight['revisionName'] || (weight['latestRevision'] ? 'the latest revision' : weight['label'])}" }.join(", ")
      end

      def swap_slot(environment_row, target, slot)
        api = api(environment_row)
        slots = api.list("#{target.id}/slots", WEB_VERSION).items.map { |each| each["name"].to_s.split("/").last }
        fail!("#{target.name} has no slot called #{slot}. Its slots are #{slots.join(', ').presence || 'none'}.") unless slots.include?(slot)

        api.post("#{target.id}/slotsswap", WEB_VERSION, { "targetSlot" => slot, "preserveVnet" => true })
        "Azure is swapping slot #{slot} with #{target.name}'s production, so what #{slot} runs goes live and what ran in production moves into #{slot}. " \
          "To undo, swap #{slot} with production again."
      end

      def move_traffic(environment_row, target, revision_name)
        api = api(environment_row)
        app = read(environment_row, target)
        configuration = app.dig("properties", "configuration").to_h
        unless configuration["activeRevisionsMode"] == MULTIPLE
          fail!("#{target.name} runs in single revision mode, where traffic cannot be sent to an earlier revision. Switch it to multiple " \
                "revision mode in the portal, or deploy the earlier image again.")
        end
        ingress = configuration["ingress"]
        fail!("#{target.name} has no ingress, so it serves no traffic to move.") if ingress.blank?

        revision = revisions(environment_row, target).find { |each| each["name"] == revision_name }
        fail!("#{target.name} has no revision called #{revision_name}. list_deployments shows them.") unless revision

        before = traffic_text(Array(ingress["traffic"]))
        api.post("#{target.id}/revisions/#{api.segment(revision_name)}/activate", APP_VERSION) unless revision.dig("properties", "active")
        api.patch(target.id, APP_VERSION, { "properties" => { "configuration" => { "ingress" => ingress.merge("traffic" => [ { "revisionName" => revision_name, "weight" => 100 } ]) } } })
        "Azure is sending all of #{target.name}'s traffic to revision #{revision_name}. Before, it went #{before.presence || 'to the latest revision'}. To undo, send it back there."
      end

      def scale_plan(environment_row, target, arguments)
        instances = count(arguments["instances"], "instances")
        fail!("An App Service plan runs 1 instance or more, so say how many with instances.") unless instances&.positive?

        api = api(environment_row)
        plan_id = read(environment_row, target).dig("properties", "serverFarmId")
        fail!("#{target.name} names no App Service plan, so there is nothing to scale.") if plan_id.blank?

        plan = api.get(plan_id, WEB_VERSION)
        tier = plan.dig("sku", "tier").to_s
        fail!("#{target.name} runs on a #{tier} plan, which adds and removes instances on its own.") if ELASTIC_TIERS.include?(tier)

        before = plan.dig("sku", "capacity")
        sites = plan.dig("properties", "numberOfSites").to_i
        # The plan's update takes no sku, so the whole plan goes back as it was read with only its instance count changed.
        api.put(plan_id, WEB_VERSION, plan.merge("sku" => plan["sku"].to_h.merge("capacity" => instances)))
        shared = sites > 1 ? " It is shared by #{sites} apps, and each now runs on #{instances} instances." : ""
        "Azure is scaling App Service plan #{plan['name']} from #{before} to #{instances} instances.#{shared} To undo, set it back to #{before}."
      end

      def scale_replicas(environment_row, target, arguments)
        minimum = count(arguments["min_replicas"], "min_replicas") || count(arguments["instances"], "instances")
        maximum = count(arguments["max_replicas"], "max_replicas")
        fail!("Give instances, min_replicas, max_replicas or a mix.") if minimum.nil? && maximum.nil?

        app = read(environment_row, target)
        template = app.dig("properties", "template").to_h
        scale = template["scale"].to_h
        ceiling = maximum || scale["maxReplicas"]
        fail!("The fewest replicas (#{minimum}) cannot be above the most (#{ceiling}). Raise max_replicas too.") if minimum && ceiling && minimum > ceiling

        wanted = scale.merge({ "minReplicas" => minimum, "maxReplicas" => maximum }.compact)
        # A partial template is not documented to merge, so the template goes back whole with only its scale changed.
        api(environment_row).patch(target.id, APP_VERSION, { "properties" => { "template" => template.merge("scale" => wanted) } })
        "Azure is setting #{target.name} to between #{wanted['minReplicas'] || 0} and #{wanted['maxReplicas'] || 'the default'} replicas, which makes a new revision. " \
          "Before, it was between #{scale['minReplicas'] || 0} and #{scale['maxReplicas'] || 'the default'}. To undo, set those again."
      end

      def site_lines(environment_row, target, site)
        properties = site["properties"].to_h
        plan = (api(environment_row).get(properties["serverFarmId"], WEB_VERSION) if properties["serverFarmId"].present?)
        config = properties["siteConfig"].to_h
        [
          "#{site['name']}, #{function?(site) ? 'a Function app' : 'an App Service app'} in #{site['location']}, #{properties['state'].to_s.downcase}" \
          "#{", availability #{properties['availabilityState'].to_s.downcase}" if properties['availabilityState']}",
          ("Plan #{plan['name']}, #{plan.dig('sku', 'tier')} #{plan.dig('sku', 'name')}, #{plan.dig('sku', 'capacity')} instances, shared by #{plan.dig('properties', 'numberOfSites')} apps" if plan),
          ("Runs #{config['linuxFxVersion'].presence || config['windowsFxVersion']}" if config["linuxFxVersion"].present? || config["windowsFxVersion"].present?),
          ("Health check #{config['healthCheckPath']}" if config["healthCheckPath"].present?),
          ("Addresses: #{Array(properties['enabledHostNames']).reject { |host| host.include?(SCM_HOST) }.join(', ')}" if properties["enabledHostNames"].present?),
          ("Last changed #{properties['lastModifiedTimeUtc']}" if properties["lastModifiedTimeUtc"])
        ]
      end

      def container_lines(app)
        properties = app["properties"].to_h
        configuration = properties["configuration"].to_h
        scale = properties.dig("template", "scale").to_h
        images = Array(properties.dig("template", "containers")).map { |container| "#{container['name']} #{container['image']}" }
        traffic = configuration.dig("ingress", "traffic").to_a
        [
          "#{app['name']}, a Container App in #{app['location']}, #{properties['runningStatus'].to_s.downcase.presence || 'unknown'}, provisioning #{properties['provisioningState'].to_s.downcase}",
          "#{configuration['activeRevisionsMode']} revision mode, latest ready revision #{properties['latestReadyRevisionName']}, latest made #{properties['latestRevisionName']}",
          ("Traffic: #{traffic_text(traffic)}" if traffic.any?),
          "Replicas: between #{scale['minReplicas'] || 0} and #{scale['maxReplicas'] || 'the default of 10'}",
          ("Runs #{images.join(', ')}" if images.any?),
          ("Address: #{configuration.dig('ingress', 'fqdn')}, #{configuration.dig('ingress', 'external') ? 'external' : 'internal'}" if configuration.dig("ingress", "fqdn"))
        ]
      end

      def sql_lines(database)
        properties = database["properties"].to_h
        [
          "#{database['name']}, an Azure SQL database in #{database['location']}, #{properties['status'].to_s.downcase}",
          "Service objective #{properties['currentServiceObjectiveName']}, sku #{database.dig('sku', 'name')} #{database.dig('sku', 'tier')}" \
          "#{", capacity #{database.dig('sku', 'capacity')}" if database.dig('sku', 'capacity')}",
          ("Largest size #{(properties['maxSizeBytes'].to_i / 1_073_741_824.0).round(1)} GB" if properties["maxSizeBytes"]),
          ("Zone redundant" if properties["zoneRedundant"]),
          ("Paused since #{properties['pausedDate']}" if properties["pausedDate"] && properties["status"].to_s == "Paused")
        ]
      end

      def postgres_lines(server)
        properties = server["properties"].to_h
        availability = properties["highAvailability"].to_h
        [
          "#{server['name']}, a PostgreSQL #{properties['version']} flexible server in #{server['location']}, #{properties['state'].to_s.downcase}",
          "Sku #{server.dig('sku', 'name')} (#{server.dig('sku', 'tier')}), storage #{properties.dig('storage', 'storageSizeGB')} GB, autogrow #{properties.dig('storage', 'autoGrow').to_s.downcase}",
          "High availability #{availability['mode'].to_s.downcase}#{", #{availability['state'].to_s.downcase}" if availability['state']}",
          ("Address: #{properties['fullyQualifiedDomainName']}" if properties["fullyQualifiedDomainName"])
        ]
      end

      # A resource's page in the portal, in the form Microsoft's own docs print it, with the tenant so the right
      # directory opens.
      # Cost Management answers columns and rows, so each row is read by its column's name: the cost, the day as a number
      # such as 20261009 or the month as a date, the service and the currency.
      def cost_text(properties, by:, started:)
        names = Array(properties["columns"]).map { |column| column["name"].to_s }
        found = Array(properties["rows"]).map { |row| names.zip(row).to_h }
        rows = found.map do |row|
          Spend::Row.new(period: cost_period((row["UsageDate"] || row["BillingMonth"]).to_s, by), service: row["ServiceName"].to_s, amount: row["Cost"].to_f)
        end
        cut = "Cost Management had more than one page, so this is the first." if properties["nextLink"].present?
        Spend.text(rows, by: by, since: started.iso8601, currency: found.first&.dig("Currency") || "USD", cut: cut)
      end

      # A day as Cost Management writes it, 20261009, as 2026-10-09, and a month as 2026-10.
      def cost_period(period, by)
        day = period.match?(/\A\d{8}\z/) ? "#{period[0, 4]}-#{period[4, 2]}-#{period[6, 2]}" : period.first(10)
        by == Spend::BY_MONTH ? day.first(7) : day
      end

      def portal_link(environment_row, resource_id)
        tenant = ConnectionSettings.of(environment_row).field(TENANT)
        portal = ConnectionSettings.of(environment_row).site
        Telemetry::Link.new(provider: PROVIDER, url: format(PORTAL_PAGE, portal: portal, tenant: tenant, id: resource_id))
      end
    end
  end
end
