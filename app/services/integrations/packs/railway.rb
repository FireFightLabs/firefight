module Integrations
  module Packs
    # Railway for one environment in each project a connection reads, one, several or every one its token can read (the
    # project connect field, a scope). It reads their services, databases and cron jobs, and their logs, metrics and
    # deployments, with an account or workspace token. Every tool reads, except the restart, rollback
    # and scale Halon uses to apply fixes. Queries and mutations are the ones the Railway CLI sends
    # (railwayapp/cli, src/gql) or Railway's API docs give (railwayapp/docs, content/docs/integrations/api).
    class Railway < NativePack
      # The environment row's credentials, which only this pack reads.
      API_TOKEN = "api_token".freeze
      PROJECT = "project".freeze
      ENVIRONMENT = "environment".freeze

      PROVIDER = "Railway".freeze
      PROVIDER_KEY = "railway".freeze
      # Railway builds from GitHub repositories and names one as owner/name (schema, ServiceSource.repo).
      GITHUB_SITE = "https://github.com".freeze

      # How the CLI tells a service instance apart (railwayapp/cli, src/resources.rs): a cron schedule makes a cron job,
      # and an image naming a database engine makes a database.
      SERVICE = "service".freeze
      DATABASE = "database".freeze
      CRON_JOB = "cron job".freeze
      KINDS = { SERVICE => ResourceMap::KIND_SERVICE, DATABASE => ResourceMap::KIND_DATABASE, CRON_JOB => ResourceMap::KIND_JOB }.freeze
      ENGINES = {
        "Postgres" => %w[postgres postgis timescale], "Redis" => %w[redis valkey], "MongoDB" => %w[mongo], "MySQL" => %w[mysql mariadb],
        "Memcached" => %w[memcached]
      }.freeze

      # Railway's three kinds of logs (docs, content/docs/observability/logs.md): what a deployment prints, its build,
      # and the HTTP requests reaching it through a public domain.
      APP = "app".freeze
      BUILD = "build".freeze
      HTTP = "http".freeze
      LOG_TYPES = [ APP, BUILD, HTTP ].freeze
      # The API answers at most 5000 lines a call (schema, deploymentLogs), and this many reads well.
      LOG_LIMIT = 200
      DEPLOYMENT_LIMIT = 20
      ROLLBACK_LOOKUP = 50

      # Each metric a tool takes, in the names every capability uses, and the measurement that answers it (schema, enum
      # MetricMeasurement). CPU is in vCPU, as the CLI labels it (src/commands/metrics.rs).
      MEASUREMENTS = {
        "cpu" => [ "CPU_USAGE", "CPU", "vCPU" ], "memory" => [ "MEMORY_USAGE_GB", "Memory", "GB" ],
        "network_in" => [ "NETWORK_RX_GB", "Network in", "GB" ], "network_out" => [ "NETWORK_TX_GB", "Network out", "GB" ],
        "disk" => [ "DISK_USAGE_GB", "Disk usage", "GB" ]
      }.freeze
      # Request counts by status code come from Railway's edge, so only for traffic through a public domain (docs,
      # content/docs/observability/metrics.md).
      HTTP_METRICS = { "requests" => [ "Requests", nil ], "http_4xx" => [ "4xx responses", "4" ], "http_5xx" => [ "5xx responses", "5" ] }.freeze
      METRICS = (MEASUREMENTS.keys + HTTP_METRICS.keys).freeze
      DEFAULT_METRICS = %w[cpu memory requests http_5xx].freeze
      DATABASE_METRICS = %w[cpu memory disk].freeze
      BASELINE_METRICS = %w[cpu memory].freeze
      PER_MINUTE = "per minute".freeze
      # A reading at least every minute, and about this many points over the range.
      MIN_SAMPLE = 60
      POINTS = 60
      BASELINE_SAMPLE = 3600
      # The CLI's own cap on replicas across regions (src/controllers/regions.rs, validate_total_replicas).
      MAX_REPLICAS = 50

      RESOURCE = { "type" => "string", "description" => "A service, database or cron job in the environment, by name or id, as list_resources shows it" }.freeze
      DEPLOYMENT = { "type" => "string", "description" => "A deployment id, as list_deployments shows it (optional, the latest)" }.freeze

      tool :list_resources,
           description: "The services, databases and cron jobs in the Railway project environment for this connection, with " \
                        "the status of each one's latest deployment. Use it first to find the name to pass to the other tools",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :describe_resource,
           description: "How one service, database or cron job is set up and how it stands now: its latest deployment and the " \
                        "state of each replica, its replicas and region, what it runs, its start command, health check, restart " \
                        "policy, whether it sleeps when idle, its schedule and its domains",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: true

      tool :search_logs,
           description: "Log lines from one service, newest first, at most #{LOG_LIMIT}. type app is what the code prints, across " \
                        "its deployments in the range. build is one deployment's build. http is the requests reaching one " \
                        "deployment through a public domain, with status and duration. Filter by text, or leave lines out with exclude",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "type" => { "type" => "string", "enum" => LOG_TYPES, "description" => "Which logs (optional, app)" },
               "deployment" => DEPLOYMENT,
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :query_metrics,
           description: "Metrics of one service or database over time: CPU, memory, network in and out and disk, and requests " \
                        "and 4xx and 5xx responses through its public domains. Returns min, average, max and latest, and the " \
                        "person sees each metric as a chart",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "metrics" => { "type" => "array", "items" => { "type" => "string", "enum" => METRICS },
                              "description" => "Which metrics (optional, the usual ones for the resource)" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :list_deployments,
           description: "A service's deployments, newest first: when, the status (SUCCESS, FAILED, CRASHED, REMOVED and the " \
                        "rest), the commit, who started it, and whether Railway can still roll back to it. The id is what " \
                        "rollback_deployment takes. Use it to see what changed before something broke",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "limit" => { "type" => "integer", "description" => "At most this many deployments (optional, #{DEPLOYMENT_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :restart_deployment,
           description: "Restart the containers of a service's latest deployment without building it again, such as one that " \
                        "crashed and ran out of restarts",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: false

      tool :rollback_deployment,
           description: "Put a service back on an earlier deployment, by the id list_deployments shows. Railway restores that " \
                        "deployment's image and variables without building, while it still keeps the image",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "deployment" => { "type" => "string", "description" => "The deployment to go back to, by its id" }
             },
             "required" => %w[resource deployment]
           },
           read_only: false

      tool :scale_service,
           description: "Set how many replicas a service runs in its region, from 1 to #{MAX_REPLICAS}. A service that runs in " \
                        "more than one region is scaled in Railway, region by region",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "instances" => { "type" => "integer", "description" => "How many replicas to run" }
             },
             "required" => %w[resource instances]
           },
           read_only: false

      def self.credential_fields
        [
          CredentialField.new(key: API_TOKEN, label: "API token", secret: true, placeholder: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                              hint: "An account token, or a workspace token for the project's workspace, created under Account Settings, Tokens. Firefight does not accept a project token, since it cannot apply fixes.")
        ]
      end

      # Reads each project chosen with the token and finds the environment in it, or for every project the token can
      # read, finds the environment in at least one, so a wrong token, project or environment is said on the form before
      # anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        token = values[API_TOKEN].to_s.strip
        projects = Array(fields[PROJECT]).map { |each| each.to_s.strip }.compact_blank
        environment = fields[ENVIRONMENT].to_s.strip
        return "Paste an API token." if token.empty?
        return "Choose at least one project, or all the token can read." if projects.empty?
        return "Enter the environment, by its name or id." if environment.empty?

        api = RailwayApi.new(token)
        if projects == [ IntegrationProvider::ConnectField::ALL ]
          listed = scope_options(values).map(&:value)
          return "This token can read no Railway projects." if listed.empty?
          return nil if listed.any? { |project| environment_in(api.project(project), environment, quiet: true) }

          return "None of the projects this token can read has an environment called #{environment}."
        end
        projects.each { |project| environment_in(api.project(project), environment) }
        nil
      rescue RailwayApi::Error => error
        Sentence.join("Railway refused this token or project", error.message.delete_prefix("Railway refused this: "))
      rescue NativePack::Error => error
        error.message
      end

      # The projects the token can read, every workspace's an account token belongs to, or a workspace token's own
      # (Integrations::RailwayApi, projects), each named with its workspace when there are several.
      def self.scope_options(values, region: nil, fields: {})
        token = values.to_h.stringify_keys[API_TOKEN].to_s.strip
        raise NativePack::Error, "Paste an API token first." if token.empty?

        api = RailwayApi.new(token)
        workspaces = begin
          api.workspaces
        rescue RailwayApi::Refused
          []
        end
        listed = workspaces.empty? ? [ [ nil, api.projects.items ] ] : workspaces.map { |workspace| [ workspace, api.projects(workspace["id"]).items ] }
        listed.flat_map do |workspace, projects|
          projects.map do |project|
            name = project["name"].presence || project["id"].to_s
            IntegrationProvider::ConnectOption.new(value: project["id"].to_s, label: workspaces.many? ? "#{workspace['name']}, #{name}" : name)
          end
        end.uniq(&:value)
      rescue RailwayApi::Error => error
        raise NativePack::Error, Sentence.join("Railway did not list this token's projects", error.message.delete_prefix("Railway refused this: "))
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_TOKEN, values[API_TOKEN].to_s.strip)
      end

      # The project's environment named by its id or name, or a refusal that lists the ones there are. quiet answers nil
      # instead of refusing.
      def self.environment_in(project, asked, quiet: false)
        environments = Array(project&.dig("environments", "edges")).filter_map { |edge| edge["node"] }
        rows = environments.map { |each| { id: each["id"], name: each["name"], environment: each } }
        found = Named.find(rows, asked, id: :id, name: :name, provider: PROVIDER)&.dig(:environment)
        return found if found || quiet

        raise NativePack::Error, "Project #{project&.dig('name') || project&.dig('id')} has no environment called #{asked}. It has " \
                                 "#{environments.map { |each| each['name'] }.join(', ').presence || 'none'}."
      end

      def list_resources(environment_row:, arguments:)
        return every_project(environment_row) { |pack| pack.list_resources(environment_row: environment_row, arguments: arguments) } if every_scope?(environment_row)

        rows = resources(environment_row).map do |resource|
          latest = resource[:instance]["latestDeployment"]
          "#{resource[:name]} (#{resource[:id]}), #{resource[:type]}, #{latest ? latest['status'].to_s.downcase : 'never deployed'}"
        end
        where = "the #{environment(environment_row)['name']} environment#{" of project #{scope_label(environment_row)}" if ConnectionSettings.of(environment_row).several_scopes?}"
        text = rows.empty? ? "#{where.upcase_first} has no services." : "#{rows.size} services in #{where}.\n#{rows.join("\n")}"
        Telemetry.result(text, link: project_link(environment_row))
      end

      def describe_resource(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        Telemetry.result(status_lines(resource).compact.join("\n"), link: link(environment_row, resource))
      end

      def search_logs(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        type = arguments["type"].presence || APP
        fail! "type must be one of #{LOG_TYPES.join(', ')}." unless LOG_TYPES.include?(type)

        started, ended = Capabilities::Answers.range(arguments)
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        lines = case type
        when APP then app_logs(environment_row, resource, started, ended, limit, arguments)
        when BUILD then build_logs(environment_row, resource, started, ended, limit, arguments)
        else http_logs(environment_row, resource, started, ended, limit, arguments)
        end
        lines = lines.sort_by(&:at).reverse.first(limit)
        asked = "the #{type} logs of #{resource[:name]} from #{started.utc.iso8601} to #{ended.utc.iso8601}"
        Telemetry.result(Telemetry.logs_text(lines, asked: asked, limit: limit), link: link(environment_row, resource))
      end

      def query_metrics(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        started, ended = Capabilities::Answers.range(arguments)
        asked = Array(arguments["metrics"]).map(&:to_s) & METRICS
        asked = (resource[:type] == DATABASE ? DATABASE_METRICS : DEFAULT_METRICS) if asked.empty?
        sample = [ ((ended - started) / POINTS).ceil, MIN_SAMPLE ].max
        page = link(environment_row, resource)
        charts = measurement_charts(environment_row, resource, asked & MEASUREMENTS.keys, started, ended, sample, page) +
                 http_charts(environment_row, resource, asked & HTTP_METRICS.keys, started, ended, sample, page)
        Telemetry.result("#{resource[:name]}\n#{Telemetry.charts_text(charts)}", charts: charts, link: page)
      end

      def list_deployments(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        deployments = api(environment_row).deployments(project_of(environment_row), environment(environment_row)["id"], resource[:id],
                                                       limit: Capabilities::Answers.limit(arguments, DEPLOYMENT_LIMIT))
        page = link(environment_row, resource)
        return Telemetry.result("#{resource[:name]} has no deployments.", link: page) if deployments.empty?

        rows = deployments.map { |deployment| deployment_line(deployment) }
        Telemetry.result("Latest #{rows.size} deployments of #{resource[:name]}, newest first. rollback_deployment takes an id " \
                         "Railway can still roll back to.\n#{rows.join("\n")}", link: page)
      end

      def restart_deployment(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        latest = resource[:instance]["latestDeployment"]
        fail! "#{resource[:name]} has no deployment to restart. Deploy it in Railway first." unless latest

        api(environment_row).restart(latest["id"])
        Telemetry.result("Railway is restarting deployment #{latest['id']} of #{resource[:name]}, without building it again.", link: link(environment_row, resource))
      end

      def rollback_deployment(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        wanted = arguments["deployment"].to_s.strip
        fail! "Say which deployment to go back to, by the id list_deployments shows." if wanted.empty?

        deployments = api(environment_row).deployments(project_of(environment_row), environment(environment_row)["id"], resource[:id], limit: ROLLBACK_LOOKUP)
        target = deployments.find { |deployment| deployment["id"] == wanted }
        fail! "Deployment #{wanted} is not among the latest #{ROLLBACK_LOOKUP} deployments of #{resource[:name]}. list_deployments shows them." unless target
        unless target["canRollback"]
          fail! "Railway can no longer roll #{resource[:name]} back to deployment #{wanted}, since it no longer keeps its image. Redeploy " \
                "the commit it ran in Railway instead, which builds it again."
        end

        api(environment_row).rollback(wanted)
        Telemetry.result("Railway is rolling #{resource[:name]} back to deployment #{wanted}, with the image and variables it had.", link: link(environment_row, resource))
      end

      def scale_service(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        count = Integer(arguments["instances"], exception: false)
        fail! "instances must be a whole number from 1 to #{MAX_REPLICAS}." unless count && count.between?(1, MAX_REPLICAS)

        regions = regions_of(resource)
        fail! "Railway has no region for #{resource[:name]} yet, so it cannot be scaled before its first deployment." if regions.empty?
        if regions.size > 1
          fail! "#{resource[:name]} runs in #{regions.keys.join(', ')}. Scale it in Railway region by region, since one number cannot say where the replicas go."
        end

        region, before = regions.first
        patch = { "services" => { resource[:id] => { "deploy" => { "multiRegionConfig" => { region => { "numReplicas" => count } } } } } }
        api(environment_row).patch_commit(environment(environment_row)["id"], patch, "Scale service #{resource[:name]} to #{count} replicas from Firefight")
        Telemetry.result("Railway is scaling #{resource[:name]} to #{count} replicas in #{region}#{" from #{before}" if before}.", link: link(environment_row, resource))
      end

      # The environment on the resource map: its services, databases and cron jobs, the repositories they build from and
      # the domains they serve.
      def map_of(environment_row)
        map_of_scopes(environment_row, kinds: MAP_KINDS) { |pack| pack.map_of_project(environment_row) }
      end

      # What a sweep puts on the map for one project.
      MAP_KINDS = (KINDS.values.uniq + [ ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ]).freeze

      def map_of_project(environment_row)
        project = project_of(environment_row)
        environment = environment(environment_row)
        account = "#{project}/#{environment['id']}"
        found = []
        links = []
        resources(environment_row).each { |resource| read_resource(environment_row, project, environment, account, resource, found, links) }
        gaps = []
        uses, endpoints = settings(environment_row, account, links, gaps)
        listed = instances(environment_row)
        if listed.incomplete?
          gaps << ResourceMap::Gap.new(text: "Only the first #{listed.items.size} services were read.",
                                       kinds: KINDS.values.uniq + [ ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ])
        end
        ResourceMap::Snapshot.new(resources: found, links: links, gaps: gaps, uses: uses, endpoints: endpoints)
      end

      # Only the service a change named (Integrations::MapEventSources::Railway), read again as the sweep reads it, with
      # where its variables point. A project's webhook sends every environment's changes, so one about another
      # environment reads nothing here. Gone only when Railway answers that the service is not there. nil for a scope
      # Railway cannot narrow to, which a sweep reads.
      def map_refresh(environment_row, scope)
        return unless scope.external_id && (scope.kind.nil? || KINDS.value?(scope.kind))
        if every_scope?(environment_row)
          holder = project_holding(environment_row, scope)
          return holder.map_refresh(environment_row, scope) if holder

          # A change in a project the connection does not read changes nothing here.
          return scope.account ? ResourceMap::Snapshot.new(resources: []) : nil
        end

        project = project_of(environment_row)
        environment = environment(environment_row)
        account = "#{project}/#{environment['id']}"
        return ResourceMap::Snapshot.new(resources: []) if scope.account && scope.account != account

        instance = begin
          api(environment_row).service_instance(environment["id"], scope.external_id)
        rescue RailwayApi::NotFound
          return ResourceMap::Snapshot.new(resources: [], gone: KINDS.values.uniq.map { |kind| [ PROVIDER_KEY, account, kind, scope.external_id ] })
        end
        return unless instance

        resource = resource_of(instance)
        found = []
        links = []
        read_resource(environment_row, project, environment, account, resource, found, links)
        gaps = []
        uses, endpoints = settings(environment_row, account, links, gaps, only: [ resource ])
        ResourceMap::Snapshot.new(resources: found, links: links, gaps: gaps, uses: uses, endpoints: endpoints)
      end

      # One service, database or cron job with the repository it builds from and the domains it serves, onto found and links.
      def read_resource(environment_row, project, environment, account, resource, found, links)
        instance = resource[:instance]
        latest = instance["latestDeployment"] || {}
        item = ResourceMap::Found.new(
          provider: PROVIDER_KEY, account: account, kind: KINDS.fetch(resource[:type]), external_id: resource[:id], name: resource[:name],
          status: latest["status"]&.downcase, url: service_url(environment_row, project, environment["id"], resource[:id]),
          details: { "type" => resource[:engine] ? "#{resource[:engine]} #{DATABASE}" : resource[:type], "instances" => instance["numReplicas"],
                     "region" => instance["region"], ResourceMap::DEPLOYED_COMMIT => latest.dig("meta", "commitHash") }.compact
        )
        found << item
        repository(item, instance.dig("source", "repo"), found, links)
        domains = instance["domains"] || {}
        (Array(domains["serviceDomains"]) + Array(domains["customDomains"])).filter_map { |domain| domain["domain"].presence }.uniq.each do |host|
          domain = ResourceMap.domain(host)
          found << domain
          links << ResourceMap::FoundLink.new(from: domain.key, to: item.key, relation: ResourceMap::RELATION_SERVED_BY)
        end
      end
      private :read_resource

      # How many services' variables one sweep reads. Railway allows a Free plan's token 100 requests an hour (docs,
      # content/docs/reference/public-api.md, Rate Limits), which the hourly sweep shares with everything else the token
      # does, so a project with more services is read a share at a time, a different share each hour.
      SETTINGS_PER_SWEEP = 20
      # A reference to another service's variable, as Railway writes it in a variable's value (docs,
      # content/docs/guides/variables.md, Reference Variables), such as ${{Postgres.DATABASE_URL}}. shared names the
      # project's shared variables, not a service.
      REFERENCE = /\$\{\{\s*([^.{}]+?)\s*\.\s*([A-Za-z0-9_]+)\s*\}\}/
      SHARED = "shared".freeze
      # Variables Railway provides each service with the names it answers on, its private domain and the public TCP
      # proxy in front of a database when it has one (docs, content/docs/reference/variables.md, Railway-provided variables).
      PRIVATE_DOMAIN = "RAILWAY_PRIVATE_DOMAIN".freeze
      PROXY_DOMAIN = "RAILWAY_TCP_PROXY_DOMAIN".freeze
      PROXY_PORT = "RAILWAY_TCP_PROXY_PORT".freeze
      # The port each database engine Railway runs listens on inside the project, as its templates set it.
      ENGINE_PORTS = { "Postgres" => 5432, "Redis" => 6379, "MongoDB" => 27_017, "MySQL" => 3306, "Memcached" => 11_211 }.freeze
      SLOWED = "Railway asked Firefight to slow down, so the rest of the services' variables were not read this time.".freeze

      # Where each service's variables point, read in memory. A reference to a database on the map is a declared link
      # naming the variable, a sealed variable is known by its name only, and a database's own private domain and TCP
      # proxy are where it is reached. Only a share of the services is read each sweep (SETTINGS_PER_SWEEP), and the
      # rest keep what an earlier sweep read. only reads those resources alone, as a re-read does, listing the others
      # only when a variable names one by its name.
      def settings(environment_row, account, links, gaps, only: nil)
        api = api(environment_row)
        share = only || share_of(resources(environment_row).sort_by { |resource| resource[:id] }, gaps)
        by_name = -> { @by_name ||= resources(environment_row).index_by { |resource| resource[:name] } }
        workspace = environment_row.integration.workspace
        share.each_with_object([ [], [] ]) do |resource, (uses, endpoints)|
          unrendered, rendered = api.service_variables(project_of(environment_row), environment(environment_row)["id"], resource[:id])
          key = [ PROVIDER_KEY, account, KINDS.fetch(resource[:type]), resource[:id] ]
          if resource[:type] == DATABASE
            endpoints.concat(database_endpoints(key, resource, rendered, workspace))
            next
          end
          declared(key, account, unrendered, by_name, links)
          sealed = rendered.select { |_, value| value.nil? }.keys
          uses.concat(ResourceMap::Use.read(from: key, workspace: workspace, values: rendered.compact.reject { |name, _| name.start_with?("RAILWAY_") },
                                            names: sealed))
        rescue Integrations::RateLimited
          gaps << ResourceMap::Gap.new(text: SLOWED, kinds: [], settings: true)
          break [ uses, endpoints ]
        rescue RailwayApi::Error => error
          gaps << ResourceMap::Gap.new(text: Sentence.join("The variables of #{resource[:name]} could not be read", error), kinds: [], settings: true)
        end
      end

      # The services this sweep reads variables for, a different share each hour when there are more than a sweep reads.
      def share_of(all, gaps)
        return all if all.size <= SETTINGS_PER_SWEEP

        gaps << ResourceMap::Gap.new(text: "The variables of #{SETTINGS_PER_SWEEP} of #{all.size} services were read this hour, to stay within " \
                                           "Railway's request limit. The others are read in the hours that follow.", kinds: [], settings: true)
        start = (Time.current.to_i / 1.hour.to_i * SETTINGS_PER_SWEEP) % all.size
        all.rotate(start).first(SETTINGS_PER_SWEEP)
      end

      # A variable set to a reference to a database on the map says outright that the service uses it.
      def declared(key, account, unrendered, by_name, links)
        unrendered.each do |name, value|
          value.to_s.scan(REFERENCE).each do |service_name, _|
            target = by_name.call[service_name] unless service_name == SHARED
            next if service_name == SHARED || target.nil? || target[:type] != DATABASE

            to = [ PROVIDER_KEY, account, ResourceMap::KIND_DATABASE, target[:id] ]
            index = links.index { |link| link.from == key && link.to == to && link.relation == ResourceMap::RELATION_USES }
            found = ResourceMap::FoundLink.new(from: key, to: to, relation: ResourceMap::RELATION_USES,
                                               variables: ((index ? links[index].variables : []) + [ name ]).uniq.sort)
            index ? links[index] = found : links << found
          end
        end
      end

      def database_endpoints(key, resource, rendered, workspace)
        private_port = ENGINE_PORTS[resource[:engine]]
        [
          (ResourceMap::Endpoint.at(resource: key, host: rendered[PRIVATE_DOMAIN], port: private_port, workspace: workspace) if private_port),
          ResourceMap::Endpoint.at(resource: key, host: rendered[PROXY_DOMAIN], port: rendered[PROXY_PORT], workspace: workspace)
        ].compact
      end
      private :settings, :share_of, :declared, :database_endpoints

      # What normal looks like for its services and databases: a week of CPU and memory, one reading an hour. A resource
      # Railway cannot read keeps yesterday's baselines, and being asked to slow down stops the whole read.
      def baselines_of(environment_row, resources, window)
        return by_scope(environment_row, resources) { |pack, group| pack.baselines_of(environment_row, group, window) } unless scope

        api = api(environment_row)
        environment_id = environment(environment_row)["id"]
        resources.flat_map do |resource|
          next [] unless KINDS.value?(resource.kind)

          answered = api.metrics("serviceId" => resource.external_id, "environmentId" => environment_id, "startDate" => window.begin.utc.iso8601,
                                 "endDate" => window.end.utc.iso8601, "sampleRateSeconds" => BASELINE_SAMPLE,
                                 "measurements" => BASELINE_METRICS.map { |name| MEASUREMENTS.fetch(name).first })
          BASELINE_METRICS.filter_map do |name|
            measurement, title, unit = MEASUREMENTS.fetch(name)
            points = answered.select { |each| each["measurement"] == measurement }.flat_map { |each| points(each["values"]) }
            ResourceMap::Baseline::Found.new(key: resource.key, metric: name, label: title, unit: unit, points: points) if points.any?
          end
        rescue Integrations::RateLimited
          raise
        rescue RailwayApi::Error => error
          Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{error.message}")
          []
        end
      end

      # Finds the environment in each project the connection reaches, so one the token can no longer read is said on the
      # connection.
      def check_health!(environment_row)
        ConnectionSettings.of(environment_row).scopes.each { |project| scoped(project).send(:environment, environment_row) }
      rescue RailwayApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        token = ConnectionSettings.of(environment_row).credential(API_TOKEN)
        fail! "This environment has no Railway token. Reconnect it on the Integrations page." if token.blank?

        RailwayApi.new(token)
      end

      def project_of(environment_row) = scope!(environment_row)

      def scope_label(environment_row) = ConnectionSettings.of(environment_row).scope_name(project_of(environment_row))

      # A listing of every project the connection reaches, each read by a pack of its own.
      def every_project(environment_row)
        texts = ConnectionSettings.of(environment_row).scopes.map do |project|
          Array(yield(scoped(project))["content"]).filter_map { |part| part["text"] }.join("\n")
        end
        Telemetry.result(texts.join("\n\n"), link: nil)
      end

      # The pack of the project a change is in, the one its account names or the one the map has the service in, or nil
      # for the sweep to find.
      def project_holding(environment_row, scope)
        reached = ConnectionSettings.of(environment_row).scopes
        named = scope.account.to_s.split("/").first
        return scoped(named) if named.present? && reached.include?(named)
        return if named.present?

        on_map = ResourceMap::Resource.present.where(workspace_id: environment_row.integration.workspace_id, provider: PROVIDER_KEY, external_id: scope.external_id)
                                      .where("resource_map_resources.integration_environment_id = :row OR resource_map_resources.sightings ? :row", row: environment_row.id.to_s)
                                      .pick(Arel.sql("details ->> '#{ResourceMap::SCOPE}'"))
        scoped(on_map) if on_map.present? && reached.include?(on_map)
      end

      def environment(environment_row)
        @environment ||= begin
          asked = ConnectionSettings.of(environment_row).field(ENVIRONMENT) || fail!("This environment has no Railway environment. Reconnect it.")
          self.class.environment_in(api(environment_row).project(project_of(environment_row)), asked)
        end
      end

      def resources(environment_row) = @resources ||= instances(environment_row).items.map { |instance| resource_of(instance) }

      def resource_of(instance)
        engine = engine_of(instance.dig("source", "image"))
        type = if instance["cronSchedule"].present? then CRON_JOB
        elsif engine then DATABASE
        else SERVICE
        end
        { id: instance["serviceId"], name: instance["serviceName"], type: type, engine: engine, instance: instance }
      end

      # The environment's service instances, as a Pages::Read that says whether they were read to the end.
      def instances(environment_row) = @instances ||= api(environment_row).service_instances(project_of(environment_row), environment(environment_row)["id"])

      # A count per step as a count per minute, so a live reading can be compared with a baseline.
      def per_minute(points, step_seconds) = points.map { |at, value| [ at, value * 60.0 / step_seconds ] }

      def engine_of(image) = ENGINES.find { |_, words| words.any? { |word| image.to_s.downcase.include?(word) } }&.first

      def find_resource(environment_row, asked)
        fail! "Say which service, by name or id. list_resources shows them." if asked.to_s.strip.empty?

        Named.find(resources(environment_row), asked, id: :id, name: :name, provider: PROVIDER, connection: environment_row) || fail!("Nothing called #{asked} in this environment. list_resources shows what there is.")
      end

      # The service page, as the CLI prints it (railwayapp/cli, src/commands/up.rs). Railway documents no address for a
      # deployment, logs or metrics page, so every result links to the service.
      def service_url(environment_row, project, environment_id, service_id) = "#{site(environment_row)}/project/#{project}/service/#{service_id}?environmentId=#{environment_id}"

      # Railway's app, the registry's site for this provider.
      def site(environment_row) = ConnectionSettings.of(environment_row).site

      def link(environment_row, resource)
        Telemetry::Link.new(provider: PROVIDER, url: service_url(environment_row, project_of(environment_row), environment(environment_row)["id"], resource[:id]))
      end

      # The project page, as railway open prints it (railwayapp/cli, src/commands/open.rs).
      def project_link(environment_row)
        Telemetry::Link.new(provider: PROVIDER, url: "#{site(environment_row)}/project/#{project_of(environment_row)}?environmentId=#{environment(environment_row)['id']}")
      end

      # Railway's log filter (docs, content/docs/observability/logs.md): quoted phrases, - to leave one out, AND between.
      def filter(*parts, arguments)
        words = parts.compact
        words << quoted(arguments["text"]) if arguments["text"].present?
        words << "-#{quoted(arguments['exclude'])}" if arguments["exclude"].present?
        words.join(" AND ").presence
      end

      def quoted(text) = "\"#{text.to_s.delete('"')}\""

      # Environment logs filtered to the service, read back from the end of the range, as the CLI reads an anchored window
      # (railwayapp/cli, src/controllers/deployment.rs, anchored_log_window).
      def app_logs(environment_row, resource, started, ended, limit, arguments)
        found = api(environment_row).environment_logs(
          "environmentId" => environment(environment_row)["id"], "filter" => filter("@service:#{resource[:id]}", arguments),
          "beforeDate" => stamp(started), "anchorDate" => stamp(ended), "afterDate" => stamp(ended), "afterLimit" => 0, "beforeLimit" => limit
        )
        found.filter_map { |line| log_line(line, line.dig("tags", "deploymentInstanceId")) }.select { |line| line.at.between?(started, ended) }
      end

      def build_logs(environment_row, resource, started, ended, limit, arguments)
        deployment = deployment_of(resource, arguments)
        found = api(environment_row).build_logs("deploymentId" => deployment, "filter" => filter(arguments), "limit" => limit,
                                                "startDate" => started.utc.iso8601, "endDate" => ended.utc.iso8601)
        found.filter_map { |line| log_line(line, deployment) }
      end

      def http_logs(environment_row, resource, started, ended, limit, arguments)
        deployment = deployment_of(resource, arguments)
        found = api(environment_row).http_logs("deploymentId" => deployment, "filter" => filter(arguments), "beforeLimit" => limit,
                                               "beforeDate" => stamp(started), "anchorDate" => stamp(ended), "afterDate" => stamp(ended), "afterLimit" => 0)
        found.filter_map do |request|
          at = Telemetry.parse_time(request["timestamp"])
          next unless at

          text = [ request["method"], "#{request['host']}#{request['path']}", request["httpStatus"], ("#{request['totalDuration']}ms" if request["totalDuration"]),
                   request["responseDetails"].presence ].compact.join(" ")
          Telemetry::LogLine.new(at: at, source: request["deploymentInstanceId"].to_s, text: text)
        end
      end

      def deployment_of(resource, arguments)
        arguments["deployment"].presence || resource[:instance].dig("latestDeployment", "id") ||
          fail!("#{resource[:name]} has no deployment yet, so it has no build or HTTP logs.")
      end

      def log_line(line, source)
        at = Telemetry.parse_time(line["timestamp"])
        return unless at

        text = line["severity"].present? ? "#{line['severity']}: #{line['message']}" : line["message"]
        Telemetry::LogLine.new(at: at, source: source.to_s, text: text)
      end

      # RFC 3339 with nanoseconds, as the CLI sends an anchored window's dates.
      def stamp(time) = time.utc.iso8601(9)

      def measurement_charts(environment_row, resource, names, started, ended, sample, page)
        return [] if names.empty?

        answered = api(environment_row).metrics("serviceId" => resource[:id], "environmentId" => environment(environment_row)["id"],
                                                "startDate" => started.utc.iso8601, "endDate" => ended.utc.iso8601, "sampleRateSeconds" => sample,
                                                "measurements" => names.map { |name| MEASUREMENTS.fetch(name).first })
        names.map do |name|
          measurement, title, unit = MEASUREMENTS.fetch(name)
          series = answered.select { |each| each["measurement"] == measurement }.map { |each| Telemetry::Series.new(label: resource[:name], points: points(each["values"])) }
          Telemetry::Chart.new(title: "#{title} of #{resource[:name]}", unit: unit, series: series.presence || [ Telemetry::Series.new(label: resource[:name], points: []) ],
                               from: started, to: ended, link: page.url)
        end
      end

      # Requests by status code at each step. The CLI adds a status's samples up as a count (src/controllers/metrics.rs),
      # so a sample is a count over its step, read here per minute.
      def http_charts(environment_row, resource, names, started, ended, sample, page)
        return [] if names.empty?

        groups = api(environment_row).http_by_status("serviceId" => resource[:id], "environmentId" => environment(environment_row)["id"],
                                                     "startDate" => started.utc.iso8601, "endDate" => ended.utc.iso8601, "stepSeconds" => sample)
        names.map do |name|
          title, digit = HTTP_METRICS.fetch(name)
          matching = groups.select { |group| digit.nil? || group["statusCode"].to_s.start_with?(digit) }
          summed = matching.flat_map { |group| points(group["samples"]) }.group_by(&:first).map { |at, pairs| [ at, pairs.sum(&:last) ] }.sort_by(&:first)
          Telemetry::Chart.new(title: "#{title} of #{resource[:name]}", unit: PER_MINUTE,
                               series: [ Telemetry::Series.new(label: resource[:name], points: per_minute(summed, sample)) ],
                               from: started, to: ended, link: page.url)
        end
      end

      # ts is an Int the schema gives no unit for, read by its size as seconds or a finer unit.
      def points(values)
        Array(values).filter_map do |point|
          at = Capabilities::Answers.time_of(point["ts"])
          [ at, point["value"].to_f ] if at && !point["value"].nil?
        end.sort_by(&:first)
      end

      # The replicas in each region, from the latest deployment's manifest, as the CLI reads them (src/controllers/regions.rs,
      # region_data_from_deployment_meta). An older deployment has one region and its replica count instead.
      def regions_of(resource)
        deploy = resource[:instance].dig("latestDeployment", "meta", "serviceManifest", "deploy") || {}
        configured = deploy["multiRegionConfig"]
        if configured.is_a?(Hash)
          return configured.select { |_, value| value.is_a?(Hash) }.transform_values { |value| value["numReplicas"] }
        end
        return { deploy["region"] => deploy["numReplicas"] || 1 } if deploy["region"].present?

        region = resource[:instance]["region"]
        region.present? ? { region => resource[:instance]["numReplicas"] } : {}
      end

      def repository(item, repo, found, links)
        path = repo.to_s.delete_prefix("#{GITHUB_SITE}/").delete_suffix(".git")
        repository = ResourceMap.repository_of("#{GITHUB_SITE}/#{path}") if path.match?(%r{\A[\w.-]+/[\w.-]+\z})
        return unless repository

        found << repository
        links << ResourceMap::FoundLink.new(from: item.key, to: repository.key, relation: ResourceMap::RELATION_BUILT_FROM)
      end

      def status_lines(resource)
        instance = resource[:instance]
        latest = instance["latestDeployment"]
        domains = instance["domains"] || {}
        hosts = (Array(domains["serviceDomains"]) + Array(domains["customDomains"])).map { |domain| "#{domain['domain']}#{" to port #{domain['targetPort']}" if domain['targetPort']}" }
        replicas = Array(latest&.dig("instances")).map { |replica| replica["status"].to_s.downcase }.tally.map { |state, count| "#{count} #{state}" }
        [
          "#{resource[:name]}, #{resource[:engine] ? "#{resource[:engine]} #{DATABASE}" : resource[:type]}",
          (latest ? "Latest deployment: #{deployment_line(latest)}" : "Never deployed"),
          ("Replicas now: #{replicas.join(', ')}" if replicas.any?),
          ("Deployment stopped by hand" if latest&.dig("deploymentStopped")),
          "Replicas: #{instance['numReplicas'] || 1}, region #{instance['region'] || 'unknown'}",
          source_line(instance),
          ("Health check: #{instance['healthcheckPath']}, timeout #{instance['healthcheckTimeout'] || 300} seconds, checked only while deploying" if instance["healthcheckPath"].present?),
          ("Health check: none, so a deployment counts as up once its container starts" if instance["healthcheckPath"].blank? && resource[:type] == SERVICE),
          "Restart policy: #{instance['restartPolicyType']}#{", at most #{instance['restartPolicyMaxRetries']} times" if instance['restartPolicyType'] == 'ON_FAILURE'}",
          ("Sleeps when idle, so a first request after a quiet spell waits for it to wake" if instance["sleepApplication"]),
          ("Schedule: #{instance['cronSchedule']}, next run #{instance['nextCronRunAt']}" if instance["cronSchedule"].present?),
          ("Domains: #{hosts.join(', ')}" if hosts.any?)
        ]
      end

      def source_line(instance)
        source = instance["source"] || {}
        what = source["repo"].present? ? "Runs #{source['repo']}" : ("Runs the image #{source['image']}" if source["image"].present?)
        [ what, ("start command #{instance['startCommand']}" if instance["startCommand"].present?) ].compact.join(", ").presence
      end

      # meta is untyped JSON. commitHash is the one key the CLI reads (src/commands/mcp/handler.rs), so the rest is read
      # only when it is there.
      def deployment_line(deployment)
        meta = deployment["meta"].is_a?(Hash) ? deployment["meta"] : {}
        commit = ("#{meta['commitHash'].to_s.first(12)}#{" \"#{meta['commitMessage'].to_s.lines.first.to_s.strip}\"" if meta['commitMessage'].present?}" if meta["commitHash"].present?)
        [ deployment["createdAt"], "deployment #{deployment['id']}", deployment["status"], commit,
          ("by #{deployment.dig('creator', 'name').presence || deployment.dig('creator', 'email')}" if deployment["creator"]),
          ("can be rolled back to" if deployment["canRollback"]) ].compact.join(", ")
      end
    end
  end
end
