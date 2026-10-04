module Integrations
  module Packs
    # Azure for one subscription per environment, read with a service principal the workspace creates: App Service and
    # Functions apps with their deployments and slots, Container Apps with their revisions, Azure SQL databases and
    # PostgreSQL flexible servers, their metrics from Azure Monitor and their logs from Log Analytics. Three tools change
    # something, each as Azure's own API does it, and only when the principal's roles allow it and an admin switched the
    # tool on: swapping a slot or moving a Container App's traffic, restarting, and scaling.
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

      WEB_VERSION = "2025-03-01".freeze
      APP_VERSION = "2025-01-01".freeze
      SQL_VERSION = "2023-08-01".freeze
      POSTGRES_VERSION = "2024-08-01".freeze
      # Azure's clouds by the key of the region the connection was made in, the first being where one with none is.
      CLOUDS = { "global" => AzureApi::GLOBAL, "us_government" => AzureApi::US_GOVERNMENT, "china" => AzureApi::CHINA }.freeze
      PORTAL = "https://portal.azure.com".freeze
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
      MISSING_TABLE = /resolve (?:table|scalar|column)/i

      DEFAULT_MINUTES = 60
      MAX_MINUTES = 7 * 24 * 60
      LOG_LIMIT = 200
      DEPLOY_LIMIT = 20
      LOG_TEXT_LIMIT = 2_000

      RANGE = {
        "minutes" => { "type" => "integer", "description" => "How far back from now, in minutes (optional, #{DEFAULT_MINUTES})" },
        "start" => { "type" => "string", "description" => "Start of the range as an ISO 8601 time, instead of minutes (optional)" },
        "end" => { "type" => "string", "description" => "End of the range as an ISO 8601 time (optional, now)" }
      }.freeze
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
               **RANGE
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
               **RANGE
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

      def self.credential_fields
        [
          CredentialField.new(key: TENANT, label: "Tenant id", secret: false, placeholder: "00000000-0000-0000-0000-000000000000",
                              hint: "The Microsoft Entra tenant the service principal belongs to, as its app registration's overview shows it."),
          CredentialField.new(key: CLIENT, label: "Client id", secret: false, placeholder: "00000000-0000-0000-0000-000000000000",
                              hint: "The service principal's application (client) id."),
          CredentialField.new(key: SECRET, label: "Client secret", secret: true, placeholder: "",
                              hint: "A client secret of that app registration. Give it Reader, Monitoring Reader and Log Analytics Reader " \
                                    "on the subscription. For Halon to apply fixes, add Website Contributor and Contributor on the apps it may change."),
          CredentialField.new(key: SUBSCRIPTION, label: "Subscription id", secret: false, placeholder: "00000000-0000-0000-0000-000000000000",
                              hint: "The Azure subscription this environment runs in.")
        ]
      end

      # Reads the subscription with the principal, so a wrong secret or subscription is said on the form before anything
      # is saved.
      def self.credential_refusal(values, region: nil)
        tenant, client, secret, subscription = values.values_at(TENANT, CLIENT, SECRET, SUBSCRIPTION).map { |value| value.to_s.strip }
        return "Enter the tenant id." if tenant.empty?
        return "Enter the client id." if client.empty?
        return "Paste the client secret." if secret.empty?
        return "Enter the subscription id, a GUID such as 00000000-0000-0000-0000-000000000000." unless subscription.match?(AzureApi::GUID)

        AzureApi.new(tenant: tenant, client_id: client, client_secret: secret, subscription: subscription, cloud: cloud_of(region)).subscription_details
        nil
      rescue AzureApi::Error => error
        "Azure refused this service principal or subscription. #{error.message}"
      end

      def self.cloud_of(region) = CLOUDS.fetch(region&.key.to_s, AzureApi::GLOBAL)

      # Replaces what was there, so a token minted with an earlier secret is never used again.
      def self.store_credentials!(environment_row, values)
        environment_row.update!(credentials: [ TENANT, CLIENT, SECRET, SUBSCRIPTION ].index_with { |key| values[key].to_s.strip }.to_json)
      end

      def list_resources(environment_row:, arguments:)
        listing = catalog(environment_row)
        rows = listing.items.map { |item| "#{item[:name]} (#{item[:id]}), #{item[:type]} in #{item[:group]}, #{item[:location]}, #{item[:status]}" }
        gaps = listing.gaps.map { |gap| "Not listed: #{gap}" }
        subscription = subscription_of(environment_row)
        text = rows.empty? ? "Subscription #{subscription} has nothing Firefight reads." : "Subscription #{subscription}, #{rows.size} resources.\n#{rows.join("\n")}"
        Telemetry.result([ text, *gaps ].join("\n"), link: portal_link(environment_row, "/subscriptions/#{subscription}"))
      end

      def search_logs(environment_row:, arguments:)
        target = find(environment_row, arguments["resource"])
        stream = arguments["stream"].presence || STREAM_APP
        fail!("stream must be one of #{STREAMS.join(', ')}.") unless STREAMS.include?(stream)

        started, ended = Telemetry.range(arguments, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)
        limit = limit(arguments, LOG_LIMIT)
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

        started, ended = Telemetry.range(arguments, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)
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
        limit = limit(arguments, DEPLOY_LIMIT)
        text = if target.site? then site_deployments(environment_row, target, limit)
        elsif target.container? then container_revisions(environment_row, target, limit)
        else fail!("#{target.name} is a #{target.type}, which has no deployments. This works on an app.")
        end
        Telemetry.result(text, link: portal_link(environment_row, target.id))
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

      def check_health!(environment_row)
        api(environment_row).subscription_details
      rescue AzureApi::Error => error
        fail! error.message
      end

      # The subscription on the resource map: its App Service and Function apps and Container Apps with the hostnames they
      # serve, its Azure SQL databases and PostgreSQL flexible servers. A list the principal may not read is a gap, and
      # nothing of its kind is taken as gone.
      def map_of(environment_row)
        subscription = subscription_of(environment_row)
        listing = catalog(environment_row)
        resources = []
        links = []
        listing.items.each do |item|
          found = ResourceMap::Found.new(provider: PROVIDER_KEY, account: subscription, kind: KINDS.fetch(item[:type]), external_id: item[:id], name: item[:name],
                                         status: item[:status], url: portal_link(environment_row, item[:id]).url, details: item[:details])
          resources << found
          item[:hosts].each do |host|
            domain = ResourceMap.domain(host)
            resources << domain
            links << ResourceMap::FoundLink.new(from: domain.key, to: found.key, relation: ResourceMap::RELATION_SERVED_BY)
          end
        end
        ResourceMap::Snapshot.new(resources: resources, links: links, gaps: listing.gaps, unread_kinds: listing.unread.map { |type| KINDS.fetch(type) }.uniq)
      end

      # What normal looks like for each app and database, read an hour at a time over the window. A resource Azure will
      # not read keeps yesterday's baselines, and being asked to slow down stops the whole read.
      def baselines_of(environment_row, resources, window)
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
        rescue AzureApi::RateLimited
          raise
        rescue AzureApi::Error => error
          Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{error.message}")
          []
        end
      end

      Listing = Data.define(:items, :gaps, :unread)

      private

      def api(environment_row)
        values = environment_row.credentials_hash
        if [ TENANT, CLIENT, SECRET, SUBSCRIPTION ].any? { |key| values[key].blank? }
          fail! "This environment has no Azure service principal. Reconnect it on the Integrations page."
        end

        @api ||= AzureApi.new(tenant: values[TENANT], client_id: values[CLIENT], client_secret: values[SECRET], subscription: values[SUBSCRIPTION],
                              cloud: self.class.cloud_of(region_of(environment_row)), token_cache: environment_row)
      end

      def region_of(environment_row) = ConnectionSettings.of(environment_row).region

      def subscription_of(environment_row) = environment_row.credentials_hash[SUBSCRIPTION].presence || fail!("This environment has no Azure subscription. Reconnect it.")

      def catalog(environment_row)
        @catalog ||= begin
          api = api(environment_row)
          root = "/subscriptions/#{api.segment(subscription_of(environment_row))}/providers"
          items = []
          gaps = []
          unread = []
          {
            "App Service and Function apps" => [ [ TYPE_WEB, TYPE_FUNCTION ], -> { api.list("#{root}/Microsoft.Web/sites", WEB_VERSION).map { |site| site_item(site) } } ],
            "Container Apps" => [ [ TYPE_CONTAINER ], -> { api.list("#{root}/Microsoft.App/containerApps", APP_VERSION).map { |app| container_item(app) } } ],
            "Azure SQL databases" => [ [ TYPE_SQL ], -> { sql_items(api, root) } ],
            "PostgreSQL flexible servers" => [ [ TYPE_POSTGRES ], -> { api.list("#{root}/Microsoft.DBforPostgreSQL/flexibleServers", POSTGRES_VERSION).map { |server| postgres_item(server) } } ]
          }.each do |what, (types, read)|
            items.concat(read.call)
          rescue AzureApi::RateLimited
            raise
          rescue AzureApi::Error => error
            gaps << "#{what} could not be read: #{error.message}"
            unread.concat(types)
          end
          Listing.new(items: items, gaps: gaps, unread: unread)
        end
      end

      def item(resource, type, status, hosts: [], details: {})
        target = Target.parse(resource["id"])
        { type: type, id: resource["id"], name: resource["name"], group: target&.group, location: resource["location"], status: status.to_s.downcase.presence || "unknown",
          hosts: hosts, details: { TYPE => type, "resource_group" => target&.group, "region" => resource["location"] }.merge(details).compact }
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
      end

      def sql_items(api, root)
        api.list("#{root}/Microsoft.Sql/servers", SQL_VERSION).flat_map do |server|
          api.list("#{server['id']}/databases", SQL_VERSION).reject { |database| database["name"] == MASTER }.map do |database|
            item(database, TYPE_SQL, database.dig("properties", "status"),
                 details: { "server" => server["name"], "sku" => database.dig("sku", "name"), "objective" => database.dig("properties", "currentServiceObjectiveName") })
          end
        end
      end

      def postgres_item(server)
        properties = server["properties"].to_h
        item(server, TYPE_POSTGRES, properties["state"],
             details: { "version" => properties["version"], "sku" => server.dig("sku", "name"), "storage_gb" => properties.dig("storage", "storageSizeGB") })
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

      def named(environment_row, wanted)
        mapped = ResourceMap::Resource.present.where(integration_environment: environment_row).where("lower(name) = ?", wanted.downcase).pluck(:external_id)
        fail!("More than one resource is called #{wanted}. Name it by its id, as list_resources shows it.") if mapped.size > 1
        return Target.parse(mapped.first) if mapped.any?

        found = catalog(environment_row).items.select { |each| each[:name].to_s.casecmp?(wanted) }
        fail!("More than one resource is called #{wanted}. Name it by its id, as list_resources shows it.") if found.size > 1

        found.first && Target.parse(found.first[:id])
      end

      def read(environment_row, target)
        version = { TYPE_WEB => WEB_VERSION, TYPE_CONTAINER => APP_VERSION, TYPE_SQL => SQL_VERSION, TYPE_POSTGRES => POSTGRES_VERSION }.fetch(target.type)
        (@read ||= {})[target.id] ||= api(environment_row).get(target.id, version)
      end

      def type_of(target, resource) = target.site? && function?(resource) ? TYPE_FUNCTION : target.type

      def revisions(environment_row, target) = api(environment_row).list("#{target.id}/revisions", APP_VERSION)

      def limit(arguments, most) = arguments["limit"].to_i.positive? ? [ arguments["limit"].to_i, most ].min : most

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

      # A Container App's logs are kept by its environment: in the environment's Log Analytics workspace, or in Azure
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
        deployments = api.list("#{target.id}/deployments", WEB_VERSION).sort_by { |deployment| deployment.dig("properties", "start_time").to_s }.reverse.first(limit)
        slots = api.list("#{target.id}/slots", WEB_VERSION).map { |slot| "#{slot['name'].to_s.split('/').last} (#{slot.dig('properties', 'state').to_s.downcase})" }
        rows = deployments.map do |deployment|
          properties = deployment["properties"].to_h
          [ properties["start_time"], DEPLOY_STATES.fetch(properties["status"], "status #{properties['status']}"), ("active" if properties["active"]),
            ("by #{properties['author'].presence || properties['deployer']}" if properties["author"].present? || properties["deployer"].present?),
            ("\"#{properties['message'].to_s.lines.first.to_s.strip}\"" if properties["message"].present?), "deployment #{deployment['name']}" ].compact.join(", ")
        end
        [ rows.any? ? "Latest #{rows.size} deployments of #{target.name}, newest first.\n#{rows.join("\n")}" : "#{target.name} has no deployments recorded.",
          slots.any? ? "Deployment slots, which rollback_app swaps with production: #{slots.join(', ')}." : "It has no deployment slots, so it cannot be rolled back by a swap." ].join("\n")
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
        slots = api.list("#{target.id}/slots", WEB_VERSION).map { |each| each["name"].to_s.split("/").last }
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
      def portal_link(environment_row, resource_id)
        tenant = environment_row.credentials_hash[TENANT]
        portal = region_of(environment_row)&.site.presence || PORTAL
        Telemetry::Link.new(provider: PROVIDER, url: format(PORTAL_PAGE, portal: portal, tenant: tenant, id: resource_id))
      end
    end
  end
end
