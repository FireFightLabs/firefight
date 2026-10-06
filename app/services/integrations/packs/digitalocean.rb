module Integrations
  module Packs
    # DigitalOcean for one team per environment: its App Platform apps, Droplets and managed databases, their logs,
    # metrics and deployments, read with a personal access token the workspace creates in DigitalOcean. Rolling an app
    # back, restarting it, scaling one of its components and rebooting a Droplet are the only tools that change anything.
    # Every path, parameter and answer is the one in DigitalOcean's OpenAPI specification (digitalocean/openapi).
    class Digitalocean < NativePack
      # The environment row's credentials, which only this pack reads.
      API_TOKEN = "api_token".freeze

      PROVIDER = DigitaloceanApi::PROVIDER
      PROVIDER_KEY = DigitaloceanApi::PROVIDER_KEY
      # Paths on the control panel, the registry's site. An app's page is /apps/<id>, the address DigitalOcean's own MCP server hands back as an app's
      # dashboard (digitalocean-labs/mcp-digitalocean). DigitalOcean documents no page of a single Droplet or database,
      # so those link to their section of the panel.
      PANEL_APPS = "apps".freeze
      PANEL_DROPLETS = "droplets".freeze
      PANEL_DATABASES = "databases".freeze

      KIND_APP = :app
      KIND_DROPLET = :droplet
      KIND_DATABASE = :database
      KIND_NAMES = { KIND_APP => "App Platform app", KIND_DROPLET => "Droplet", KIND_DATABASE => "managed database" }.freeze
      MAP_KINDS = { KIND_APP => ResourceMap::KIND_SERVICE, KIND_DROPLET => ResourceMap::KIND_VIRTUAL_MACHINE,
                    KIND_DATABASE => ResourceMap::KIND_DATABASE }.freeze
      # What each list puts on the map. An app also puts the domains it serves and the repositories it builds from there.
      LISTED_KINDS = { KIND_APP => [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ],
                       KIND_DROPLET => [ ResourceMap::KIND_VIRTUAL_MACHINE ], KIND_DATABASE => [ ResourceMap::KIND_DATABASE ] }.freeze

      # The log types of apps_get_logs, as the API names them.
      LOG_TYPES = %w[RUN BUILD DEPLOY RUN_RESTARTED].freeze
      DEFAULT_LOG_TYPE = LOG_TYPES.first
      # The components of an app spec that run instances (app_component_instance_base), and the ones that are scaled.
      COMPONENT_LISTS = %w[services workers jobs static_sites functions].freeze
      SCALED_LISTS = %w[services workers].freeze
      REBOOT = "reboot".freeze
      MYSQL = "mysql".freeze
      # The code host sources of an app component, by the names app_component_base gives them (owner/name in repo), and a
      # plain git source, which names its clone address.
      SOURCES = %w[github gitlab bitbucket].freeze
      GIT = "git".freeze

      CPU = "cpu".freeze
      MEMORY = "memory".freeze
      RESTARTS = "restarts".freeze
      DISK = "disk".freeze
      NETWORK_IN = "network_in".freeze
      NETWORK_OUT = "network_out".freeze
      METRICS = [ CPU, MEMORY, RESTARTS, DISK, NETWORK_IN, NETWORK_OUT ].freeze
      # What each kind keeps under /v2/monitoring/metrics. A Droplet's CPU, memory and disk are worked out from the
      # counters DigitalOcean answers with, and a database's metrics exist for MySQL only.
      KIND_METRICS = {
        KIND_APP => [ CPU, MEMORY, RESTARTS ], KIND_DROPLET => [ CPU, MEMORY, DISK, NETWORK_IN, NETWORK_OUT ],
        KIND_DATABASE => [ CPU, MEMORY, DISK ]
      }.freeze
      DEFAULT_METRICS = { KIND_APP => [ CPU, MEMORY, RESTARTS ], KIND_DROPLET => [ CPU, MEMORY, DISK ], KIND_DATABASE => [ CPU, MEMORY, DISK ] }.freeze
      BASELINE_METRICS = { KIND_APP => [ CPU, MEMORY ], KIND_DROPLET => [ CPU, MEMORY, DISK ], KIND_DATABASE => [ CPU, MEMORY, DISK ] }.freeze
      APP_PATHS = { CPU => "apps/cpu_percentage", MEMORY => "apps/memory_percentage", RESTARTS => "apps/restart_count" }.freeze
      DATABASE_PATHS = { CPU => [ "database/mysql/cpu_usage", "avg" ], MEMORY => [ "database/mysql/memory_usage", "avg" ],
                         DISK => [ "database/mysql/disk_usage", "max" ] }.freeze
      TITLES = { CPU => "CPU", MEMORY => "Memory", RESTARTS => "Restarts", DISK => "Disk used", NETWORK_IN => "Network in",
                 NETWORK_OUT => "Network out" }.freeze
      PERCENT = "%".freeze
      UNITS = { CPU => PERCENT, MEMORY => PERCENT, RESTARTS => "count", DISK => PERCENT, NETWORK_IN => "Mbps", NETWORK_OUT => "Mbps" }.freeze
      IDLE = "idle".freeze
      LOG_LIMIT = 200
      DEPLOYMENT_LIMIT = 20
      # A log line starts with the component and an RFC 3339 time, as App Platform writes it.
      LOG_LINE = /\A(?<source>\S+)\s+(?<at>\d{4}-\d{2}-\d{2}T\S+)\s?(?<text>.*)\z/

      RANGE = Capabilities::RANGE
      RESOURCE = { "type" => "string", "description" => "An App Platform app, a Droplet or a managed database, by name or id, as list_resources shows it" }.freeze
      APP = { "type" => "string", "description" => "An App Platform app, by name or id, as list_resources shows it" }.freeze
      COMPONENT = { "type" => "string", "description" => "One component of the app, by its name in the app spec, as describe_resource shows it" }.freeze

      tool :list_resources,
           description: "The App Platform apps, Droplets and managed databases this token can see, with what each is and how it " \
                        "stands. Use it first to find the name to pass to the other tools",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :describe_resource,
           description: "How one app, Droplet or database is set up and how it stands now. An app: its active and in-progress " \
                        "deployments, whether it is pinned by a rollback, each component's instances, size, source and health, " \
                        "and its domains. A Droplet: status, size, image, region and addresses. A database: engine, version, " \
                        "status, nodes, size, storage and maintenance window. Never secrets or connection details",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: true

      tool :app_logs,
           description: "Log lines of an App Platform app's active deployment, newest first, at most #{LOG_LIMIT}. type picks run " \
                        "logs (what the app prints), build, deploy, or RUN_RESTARTED for instances that crashed or restarted. " \
                        "Filter by text or a regular expression, and to one component",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => APP, "component" => COMPONENT.merge("description" => "#{COMPONENT['description']} (optional, every component)"),
               "type" => { "type" => "string", "enum" => LOG_TYPES, "description" => "Which logs (optional, #{DEFAULT_LOG_TYPE})" },
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "regex" => { "type" => "string", "description" => "Only lines matching this regular expression (optional)" },
               "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :list_deployments,
           description: "An App Platform app's deployments, newest first: when each was made, its phase, what caused it, the " \
                        "commit each component was built from, and its id, which rollback_app takes",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => APP,
               "limit" => { "type" => "integer", "description" => "At most this many deployments (optional, #{DEPLOYMENT_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :resource_metrics,
           description: "Metrics of one app, Droplet or MySQL database over time, with min, average, max and latest for each, " \
                        "and the person sees each as a chart. An app keeps cpu, memory and restarts per instance, a Droplet " \
                        "cpu, memory, disk, network_in and network_out, and a MySQL database cpu, memory and disk",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "metrics" => { "type" => "array", "items" => { "type" => "string", "enum" => METRICS },
                              "description" => "Which metrics (optional, the resource's usual ones)" },
               **RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :rollback_app,
           description: "Put an App Platform app back on an earlier deployment, by the id list_deployments shows. DigitalOcean " \
                        "pins the app to it, so no new deployment goes out, not even on a push, until someone commits or " \
                        "reverts the rollback in the control panel",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => APP,
               "deployment" => { "type" => "string", "description" => "The deployment to go back to, by its id" }
             },
             "required" => %w[resource deployment]
           },
           read_only: false

      tool :restart_app,
           description: "A rolling restart of an App Platform app, every component or one, for one stuck in a bad state while " \
                        "its code is fine. It makes a new deployment of the same code",
           params_schema: {
             "type" => "object",
             "properties" => { "resource" => APP, "component" => COMPONENT.merge("description" => "#{COMPONENT['description']} (optional, every component)") },
             "required" => [ "resource" ]
           },
           read_only: false

      tool :scale_app,
           description: "Set how many instances one service or worker of an App Platform app runs. Everything else in the app's " \
                        "spec stays as it is, and the same code is redeployed. A component that autoscales is refused",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => APP,
               "component" => COMPONENT.merge("description" => "#{COMPONENT['description']} (optional when the app has one service or worker)"),
               "instances" => { "type" => "integer", "description" => "How many instances to run, 1 or more" }
             },
             "required" => %w[resource instances]
           },
           read_only: false

      tool :reboot_droplet,
           description: "Reboot a Droplet gracefully, as the reboot command on it would, for one that hangs or misbehaves while " \
                        "its disk and setup are fine",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: false

      def self.credential_fields
        [
          CredentialField.new(key: API_TOKEN, label: "Personal access token", secret: true, placeholder: "dop_v1_...",
                              hint: "A DigitalOcean personal access token with the account:read, app:read, droplet:read, database:read and " \
                                    "monitoring:read scopes. For Halon to roll back, restart or scale apps and reboot Droplets, add app:update and droplet:update.")
        ]
      end

      # Reads the account with the token, so a wrong or expired token is said on the form before anything is saved.
      def self.credential_refusal(values, region: nil)
        token = values[API_TOKEN].to_s.strip
        return "Paste a personal access token." if token.empty?

        DigitaloceanApi.new(token).account
        nil
      rescue DigitaloceanApi::Error => error
        Sentence.join("DigitalOcean refused this token", error)
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_TOKEN, values[API_TOKEN].to_s.strip)
      end

      def list_resources(environment_row:, arguments:)
        api = api(environment_row)
        rows = api.apps.items.map { |app| "#{app_name(app)} (#{app['id']}), App Platform app, #{app_phase(app)}" }
        rows += api.droplets.items.map { |droplet| "#{droplet['name']} (#{droplet['id']}), Droplet, #{droplet['status']}" }
        rows += api.databases.items.map { |database| "#{database['name']} (#{database['id']}), #{database['engine']} database, #{database['status']}" }
        return Telemetry.result("This token sees no apps, Droplets or databases.", link: panel_link(environment_row)) if rows.empty?

        Telemetry.result("#{rows.size} apps, Droplets and databases.\n#{rows.join("\n")}", link: panel_link(environment_row))
      end

      def describe_resource(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        lines = case resource[:kind]
        when KIND_APP then app_lines(environment_row, resource)
        when KIND_DROPLET then droplet_lines(api(environment_row).droplet(resource[:id]))
        else database_lines(api(environment_row).database(resource[:id]))
        end
        Telemetry.result(lines.compact.join("\n"), link: link_of(environment_row, resource))
      end

      def app_logs(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"], only: KIND_APP)
        type = arguments["type"].presence || DEFAULT_LOG_TYPE
        fail!("type must be one of #{LOG_TYPES.join(', ')}.") unless LOG_TYPES.include?(type)
        started, ended = Capabilities::Answers.range(arguments)
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        api = api(environment_row)
        raw = api.log_urls(resource[:id], type: type, component: arguments["component"].presence).flat_map { |url| api.log_file(url).lines }
        lines = raw.filter_map { |line| log_line(line, ended) }
                   .select { |line| line.at.between?(started, ended) && matches?(line.text, arguments) }
                   .sort_by(&:at).reverse.first(limit)
        asked = "#{type} logs of #{resource[:name]}#{" (#{arguments['component']})" if arguments['component'].present?} from #{started.utc.iso8601} to #{ended.utc.iso8601}"
        Telemetry.result(Telemetry.logs_text(lines, asked: asked, limit: limit), link: link_of(environment_row, resource))
      end

      def list_deployments(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"], only: KIND_APP)
        deployments = api(environment_row).deployments(resource[:id], limit: Capabilities::Answers.limit(arguments, DEPLOYMENT_LIMIT))
        return Telemetry.result("#{resource[:name]} has no deployments.", link: link_of(environment_row, resource)) if deployments.empty?

        rows = deployments.map { |deployment| deployment_line(deployment) }
        Telemetry.result("Latest #{rows.size} deployments of #{resource[:name]}, newest first. rollback_app takes a deployment id.\n#{rows.join("\n")}",
             link: link_of(environment_row, resource))
      end

      def resource_metrics(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        kept = kept_metrics(environment_row, resource)
        asked = Array(arguments["metrics"]).map(&:to_s).uniq.presence || DEFAULT_METRICS.fetch(resource[:kind])
        missing = asked - kept
        fail!("DigitalOcean does not keep #{missing.join(', ')} for #{resource[:name]}. It keeps #{kept.join(', ')}.") if missing.any?

        started, ended = Capabilities::Answers.range(arguments)
        api = api(environment_row)
        charts = asked.map do |metric|
          series = series_of(api, resource, metric, started, ended)
          Telemetry::Chart.new(title: "#{TITLES.fetch(metric)} of #{resource[:name]}", unit: UNITS.fetch(metric), series: series,
                               from: started, to: ended, link: link_of(environment_row, resource).url)
        end
        Telemetry.result("#{resource[:name]}\n#{Telemetry.charts_text(charts)}", charts: charts, link: link_of(environment_row, resource))
      end

      def rollback_app(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"], only: KIND_APP)
        deployment = arguments["deployment"].to_s.strip
        fail!("Say which deployment to go back to, by the id list_deployments shows.") if deployment.empty?

        made = change { api(environment_row).rollback(resource[:id], deployment) }
        Telemetry.result("#{resource[:name]} is rolling back to deployment #{deployment}, as new deployment #{made.dig('deployment', 'id') || 'unknown'}. " \
             "DigitalOcean pins the app to it, so no new deployment goes out, not even on a push, until someone commits or reverts " \
             "the rollback in the control panel.", link: link_of(environment_row, resource))
      end

      def restart_app(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"], only: KIND_APP)
        component = arguments["component"].to_s.strip.presence
        if component && component_of(api(environment_row).app(resource[:id])["spec"], component, COMPONENT_LISTS).nil?
          fail!("#{resource[:name]} has no component called #{component}. describe_resource lists them.")
        end

        made = change { api(environment_row).restart(resource[:id], Array(component)) }
        Telemetry.result("#{component || 'Every component'} of #{resource[:name]} is restarting, as deployment #{made.dig('deployment', 'id') || 'unknown'}.",
             link: link_of(environment_row, resource))
      end

      # The whole spec goes back as DigitalOcean returned it, with only the one instance count changed, since the API
      # replaces the app's spec with what it is sent. update_all_source_versions stays off, so no new code goes out.
      def scale_app(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"], only: KIND_APP)
        count = Integer(arguments["instances"], exception: false)
        fail!("instances must be a whole number, 1 or more.") unless count && count >= 1

        spec = api(environment_row).app(resource[:id])["spec"].to_h.deep_dup
        component = scaled_component(resource, spec, arguments["component"].to_s.strip.presence)
        if component["autoscaling"].present?
          fail!("#{component['name']} autoscales between #{component.dig('autoscaling', 'min_instance_count')} and " \
                "#{component.dig('autoscaling', 'max_instance_count')} instances, so its count cannot be set. Change its autoscaling in the control panel.")
        end

        before = component["instance_count"] || 1
        component["instance_count"] = count
        change { api(environment_row).update_app(resource[:id], spec) }
        Telemetry.result("#{component['name']} of #{resource[:name]} goes from #{before} to #{count} instances, redeploying the same code.", link: link_of(environment_row, resource))
      end

      def reboot_droplet(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"], only: KIND_DROPLET)
        action = change { api(environment_row).droplet_action(resource[:id], REBOOT) }
        Telemetry.result("#{resource[:name]} is rebooting, action #{action.dig('action', 'id') || 'unknown'} #{action.dig('action', 'status')}.".squish,
             link: link_of(environment_row, resource))
      end

      # The team on the resource map: its apps, the domains they serve and the repositories they build from, its Droplets
      # and its databases. A list the token may not read is a gap in the map, not a failed sweep.
      def map_of(environment_row)
        api = api(environment_row)
        account = account_of(api)
        resources = []
        links = []
        gaps = []
        { KIND_APP => -> { api.apps }, KIND_DROPLET => -> { api.droplets }, KIND_DATABASE => -> { api.databases } }.each do |kind, read|
          listed = read.call
          listed.items.each { |row| map_row(environment_row, kind, row, account, resources, links) }
          if listed.incomplete?
            gaps << ResourceMap::Gap.new(text: "Only the first #{listed.items.size} #{KIND_NAMES.fetch(kind)}s were read.", kinds: LISTED_KINDS.fetch(kind))
          end
        rescue Integrations::RateLimited
          raise
        rescue DigitaloceanApi::Error => error
          gaps << ResourceMap::Gap.new(text: Sentence.join("The #{KIND_NAMES.fetch(kind)}s could not be read", error), kinds: LISTED_KINDS.fetch(kind))
        end
        ResourceMap::Snapshot.new(resources: resources, links: links, gaps: gaps)
      end

      # What normal looks like for its apps, Droplets and MySQL databases, one metrics read each. Instances are averaged,
      # a disk is its fullest mount. A resource DigitalOcean cannot read keeps yesterday's baselines, and being asked to
      # slow down stops the whole read.
      def baselines_of(environment_row, resources, window)
        api = api(environment_row)
        resources.flat_map do |resource|
          kind = MAP_KINDS.key(resource.kind)
          next [] unless kind
          next [] if kind == KIND_DATABASE && resource.details["engine"] != MYSQL

          read = { kind: kind, id: resource.external_id, name: resource.name }
          BASELINE_METRICS.fetch(kind).filter_map do |metric|
            points = combined(series_of(api, read, metric, window.begin, window.end), metric)
            ResourceMap::Baseline::Found.new(key: resource.key, metric: metric, label: TITLES.fetch(metric), unit: UNITS.fetch(metric), points: points) if points.any?
          end
        rescue Integrations::RateLimited
          raise
        rescue DigitaloceanApi::Error => error
          Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{error.message}")
          []
        end
      end

      def check_health!(environment_row)
        api(environment_row).account
      rescue DigitaloceanApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        token = ConnectionSettings.of(environment_row).credential(API_TOKEN)
        fail! "This environment has no DigitalOcean token. Reconnect it on the Integrations page." if token.blank?

        DigitaloceanApi.new(token)
      end

      # The team's name, or the account's id when it belongs to no team.
      def account_of(api)
        account = api.account
        account.dig("team", "name").presence || account["uuid"].to_s
      end

      def map_row(environment_row, kind, row, account, resources, links)
        case kind
        when KIND_APP then map_app(environment_row, row, account, resources, links)
        when KIND_DROPLET
          resources << found(environment_row, kind, row["id"], row["name"], account, status: row["status"],
                             details: { "size" => row["size_slug"], "region" => row.dig("region", "slug"), "image" => row.dig("image", "distribution"),
                                        ResourceMap::TAGS => tags_of(row) }.compact)
        else
          resources << found(environment_row, kind, row["id"], row["name"], account, status: row["status"],
                             details: { "engine" => row["engine"], "version" => row["version"], "nodes" => row["num_nodes"],
                                        "size" => row["size"], "region" => row["region"], ResourceMap::TAGS => tags_of(row) }.compact)
        end
      end

      # DigitalOcean's tags are plain words with no value, so each is kept as a key alone.
      def tags_of(row) = Array(row["tags"]).to_h { |tag| [ tag.to_s, nil ] }.presence

      def map_app(environment_row, app, account, resources, links)
        spec = app["spec"].to_h
        commit = Array(app.dig("active_deployment", "services")).filter_map { |service| service["source_commit_hash"].presence }.first
        app_found = found(environment_row, KIND_APP, app["id"], app_name(app), account, status: app_phase(app).downcase,
                          details: { "region" => app.dig("region", "slug"), "tier" => app["tier_slug"], ResourceMap::DEPLOYED_COMMIT => commit,
                                     "components" => components(spec).size }.compact)
        resources << app_found
        components(spec).filter_map { |component| repository_of(component) }.uniq.each do |repository|
          resources << repository
          links << ResourceMap::FoundLink.new(from: app_found.key, to: repository.key, relation: ResourceMap::RELATION_BUILT_FROM)
        end
        hosts = [ app["live_domain"], *Array(spec["domains"]).map { |domain| domain["domain"] } ].compact_blank.uniq
        hosts.each do |host|
          domain = ResourceMap.domain(host)
          resources << domain
          links << ResourceMap::FoundLink.new(from: domain.key, to: app_found.key, relation: ResourceMap::RELATION_SERVED_BY)
        end
      end

      # The repository a component builds from, on whichever code host the registry has a site for, or nil.
      def repository_of(component)
        source = SOURCES.find { |key| component.dig(key, "repo").present? }
        return ResourceMap.repository(source, component.dig(source, "repo")) if source

        clone = component.dig(GIT, "repo_clone_url")
        clone.present? ? ResourceMap.repository_of(clone) : nil
      end

      def found(environment_row, kind, id, name, account, status: nil, details: {})
        ResourceMap::Found.new(provider: PROVIDER_KEY, account: account, kind: MAP_KINDS.fetch(kind), external_id: id.to_s,
                               name: name.presence || id.to_s, status: status.presence, url: page(environment_row, kind, id), details: details)
      end

      def page(environment_row, kind, id)
        panel = panel(environment_row)
        case kind
        when KIND_APP then "#{panel}/#{PANEL_APPS}/#{Http.segment(id)}"
        when KIND_DROPLET then "#{panel}/#{PANEL_DROPLETS}"
        else "#{panel}/#{PANEL_DATABASES}"
        end
      end

      def link_of(environment_row, resource) = Telemetry::Link.new(provider: PROVIDER, url: page(environment_row, resource[:kind], resource[:id]))

      def panel_link(environment_row) = Telemetry::Link.new(provider: PROVIDER, url: panel(environment_row))

      # The control panel, the registry's site for DigitalOcean.
      def panel(environment_row) = ConnectionSettings.of(environment_row).site.to_s.chomp("/")

      # A change that DigitalOcean refuses for want of a scope says which to give the token.
      def change
        yield
      rescue Integrations::RateLimited
        raise
      rescue DigitaloceanApi::Error => error
        raise unless error.message.match?(/answered 40[13]/)

        fail!(Sentence.join("DigitalOcean refused this change", error,
                            after: "The token cannot make it. In DigitalOcean, give it the app:update scope for apps or droplet:update for " \
                                   "Droplets, then run it again"))
      end

      # By id, then by name, looking only where the kind can be, so a tool for apps never lists Droplets. Two resources of
      # one name are never picked for the agent, so it names one by id.
      def find_resource(environment_row, asked, only: nil)
        wanted = asked.to_s.strip.downcase
        fail! "Say which app, Droplet or database, by name or id. list_resources shows them." if wanted.empty?

        api = api(environment_row)
        readers = { KIND_APP => -> { api.apps.items.map { |app| { kind: KIND_APP, id: app["id"].to_s, name: app_name(app) } } },
                    KIND_DROPLET => -> { api.droplets.items.map { |droplet| { kind: KIND_DROPLET, id: droplet["id"].to_s, name: droplet["name"].to_s } } },
                    KIND_DATABASE => -> { api.databases.items.map { |database| { kind: KIND_DATABASE, id: database["id"].to_s, name: database["name"].to_s } } } }
        listed = readers.slice(*(only ? [ only ] : readers.keys)).values.flat_map(&:call)
        found = Named.find(listed, asked, id: :id, name: :name, provider: PROVIDER, describe: ->(row) { "#{KIND_NAMES.fetch(row[:kind])} #{row[:id]}" }, connection: environment_row)
        return found if found

        what = only ? "#{KIND_NAMES.fetch(only)} called #{asked}" : "app, Droplet or database called #{asked}"
        fail!("No #{what} on this DigitalOcean account. list_resources shows what there is.")
      end

      def app_name(app) = app.dig("spec", "name").presence || app["id"].to_s

      # The phase of the deployment in progress when there is one, else the active one's.
      def app_phase(app)
        (app.dig("in_progress_deployment", "phase") || app.dig("active_deployment", "phase") || "UNKNOWN").to_s
      end

      def components(spec) = COMPONENT_LISTS.flat_map { |list| Array(spec.to_h[list]).map { |component| component.merge("type" => list.singularize) } }

      def component_of(spec, name, lists)
        lists.flat_map { |list| Array(spec.to_h[list]) }.find { |component| component["name"].to_s.casecmp?(name) }
      end

      def scaled_component(resource, spec, name)
        if name
          return component_of(spec, name, SCALED_LISTS) || fail!("#{resource[:name]} has no service or worker called #{name}. describe_resource lists them.")
        end

        scaled = SCALED_LISTS.flat_map { |list| Array(spec[list]) }
        return scaled.first if scaled.one?

        fail!("#{resource[:name]} has #{scaled.size} services and workers, so call scale_app with the component to scale: " \
              "#{scaled.map { |component| component['name'] }.join(', ')}.")
      end

      def app_lines(environment_row, resource)
        api = api(environment_row)
        app = api.app(resource[:id])
        health = begin
          Array(api.health(resource[:id])["components"]).index_by { |component| component["name"] }
        rescue DigitaloceanApi::Error
          {}
        end
        active = app["active_deployment"] || {}
        progress = app["in_progress_deployment"]
        [
          "#{app_name(app)}, App Platform app in #{app.dig('region', 'slug') || 'an unknown region'}#{", tier #{app['tier_slug']}" if app['tier_slug']}",
          ("Active deployment: #{active['id']}, #{active['phase']}, made #{active['created_at']}, #{active['cause']}".squish if active.any?),
          ("In progress: deployment #{progress['id']}, #{progress['phase']}, since #{progress['created_at']}" if progress),
          ("Pinned to deployment #{app.dig('pinned_deployment', 'id')} by a rollback, so nothing new deploys until it is committed or reverted." if app["pinned_deployment"]),
          ("Live at #{app['live_url']}" if app["live_url"]),
          "Components:",
          *components(app["spec"]).map { |component| component_line(component, health[component["name"]]) },
          domain_lines(app)
        ]
      end

      def component_line(component, health)
        source = if component["github"] then "github #{component.dig('github', 'repo')} branch #{component.dig('github', 'branch')}"
        elsif component["gitlab"] then "gitlab #{component.dig('gitlab', 'repo')} branch #{component.dig('gitlab', 'branch')}"
        elsif component["image"] then "image #{component.dig('image', 'repository')}:#{component.dig('image', 'tag') || component.dig('image', 'digest')}"
        end
        scale = component["autoscaling"] ? "autoscales #{component.dig('autoscaling', 'min_instance_count')} to #{component.dig('autoscaling', 'max_instance_count')}" : ("#{component['instance_count'] || 1} instances" if SCALED_LISTS.include?(component["type"].pluralize))
        state = health && "#{health['state']}, #{health['replicas_ready']} of #{health['replicas_desired']} ready, CPU #{health['cpu_usage_percent']&.round(1)}%, memory #{health['memory_usage_percent']&.round(1)}%"
        check = component["health_check"] || component["liveness_health_check"]
        "- #{component['name']} (#{component['type']}): #{[ scale, component['instance_size_slug'], source, state, ("health check #{check['http_path'] || "port #{check['port']}"}" if check) ].compact.join(', ')}"
      end

      def domain_lines(app)
        domains = Array(app["domains"]).map { |domain| "#{domain.dig('spec', 'domain')} #{domain['phase']}#{", certificate until #{domain['certificate_expires_at']}" if domain['certificate_expires_at']}" }
        "Domains: #{domains.join(', ')}" if domains.any?
      end

      def droplet_lines(droplet)
        addresses = Array(droplet.dig("networks", "v4")).map { |network| "#{network['ip_address']} #{network['type']}" }
        [
          "#{droplet['name']}, Droplet #{droplet['id']}, #{droplet['status']}#{', locked' if droplet['locked']}",
          "Size #{droplet['size_slug']}: #{droplet['vcpus']} vCPUs, #{droplet['memory']} MB memory, #{droplet['disk']} GB disk, in #{droplet.dig('region', 'slug')}",
          ("Image: #{droplet.dig('image', 'distribution')} #{droplet.dig('image', 'name')}" if droplet["image"]),
          ("Addresses: #{addresses.join(', ')}" if addresses.any?),
          ("Tags: #{droplet['tags'].join(', ')}" if droplet["tags"].present?),
          "Created #{droplet['created_at']}"
        ]
      end

      # Only describing fields, never connection, users or anything else that carries a password.
      def database_lines(database)
        window = database["maintenance_window"]
        [
          "#{database['name']}, #{database['engine']} #{database['version']} database, #{database['status']}",
          "#{database['num_nodes']} nodes of #{database['size']} in #{database['region']}#{", #{database['storage_size_mib']} MiB storage" if database['storage_size_mib']}",
          ("Maintenance window: #{window['day']} #{window['hour']}#{', updates pending' if window['pending']}" if window),
          ("Version end of life: #{database['version_end_of_life']}" if database["version_end_of_life"]),
          "Created #{database['created_at']}"
        ]
      end

      def deployment_line(deployment)
        commits = Array(deployment["services"]).filter_map { |service| "#{service['name']} #{service['source_commit_hash'].to_s.first(12)}" if service["source_commit_hash"].present? }
        [ deployment["created_at"], "deployment #{deployment['id']}", deployment["phase"], deployment["cause"].presence,
          ("cloned from #{deployment['cloned_from']}" if deployment["cloned_from"].present?), ("commits #{commits.join(', ')}" if commits.any?) ].compact.join(", ")
      end

      def log_line(line, fallback)
        text = line.to_s.chomp
        return nil if text.strip.empty?

        parsed = text.match(LOG_LINE)
        at = parsed && Telemetry.parse_time(parsed[:at])
        at ? Telemetry::LogLine.new(at: at, source: parsed[:source], text: parsed[:text]) : Telemetry::LogLine.new(at: fallback, source: "", text: text)
      end

      def matches?(text, arguments)
        return false if arguments["text"].present? && !text.include?(arguments["text"])
        return false if arguments["exclude"].present? && text.include?(arguments["exclude"])
        return true if arguments["regex"].blank?

        Regexp.new(arguments["regex"], timeout: 1).match?(text)
      rescue RegexpError
        fail!("regex is not a regular expression Firefight can read.")
      end

      # Only MySQL databases have metrics in the API.
      def kept_metrics(environment_row, resource)
        return KIND_METRICS.fetch(resource[:kind]) unless resource[:kind] == KIND_DATABASE

        engine = api(environment_row).database(resource[:id])["engine"]
        fail!("DigitalOcean's API keeps metrics only for MySQL databases, and #{resource[:name]} is #{engine}. Read its status instead.") unless engine == MYSQL

        KIND_METRICS.fetch(KIND_DATABASE)
      end

      def window(started, ended) = { "start" => started.to_i, "end" => ended.to_i }

      def series_of(api, resource, metric, started, ended)
        case resource[:kind]
        when KIND_APP
          rows = api.metrics(APP_PATHS.fetch(metric), window(started, ended).merge("app_id" => resource[:id]))
          rows.map { |row| Telemetry::Series.new(label: row.dig("metric", "app_component_instance") || row.dig("metric", "app_component") || resource[:name], points: points(row)) }
        when KIND_DATABASE
          path, aggregate = DATABASE_PATHS.fetch(metric)
          rows = api.metrics(path, window(started, ended).merge("db_id" => resource[:id], "aggregate" => aggregate))
          rows.map { |row| Telemetry::Series.new(label: resource[:name], points: points(row)) }
        else droplet_series(api, resource, metric, started, ended)
        end
      end

      def droplet_series(api, resource, metric, started, ended)
        query = window(started, ended).merge("host_id" => resource[:id])
        case metric
        when CPU then [ Telemetry::Series.new(label: resource[:name], points: cpu_points(api.metrics("droplet/cpu", query))) ]
        when MEMORY
          total = points(api.metrics("droplet/memory_total", query).first).to_h
          available = points(api.metrics("droplet/memory_available", query).first)
          used = available.filter_map { |at, free| (size = total[at]) && size.positive? && [ at, (1 - (free / size)) * 100 ] }
          [ Telemetry::Series.new(label: resource[:name], points: used) ]
        when DISK
          sizes = api.metrics("droplet/filesystem_size", query).index_by { |row| row.dig("metric", "mountpoint") }
          api.metrics("droplet/filesystem_free", query).map do |row|
            mount = row.dig("metric", "mountpoint")
            total = points(sizes[mount]).to_h
            used = points(row).filter_map { |at, free| (size = total[at]) && size.positive? && [ at, (1 - (free / size)) * 100 ] }
            Telemetry::Series.new(label: mount || resource[:name], points: used)
          end
        else
          direction = metric == NETWORK_IN ? "inbound" : "outbound"
          rows = api.metrics("droplet/bandwidth", query.merge("interface" => "public", "direction" => direction))
          rows.map { |row| Telemetry::Series.new(label: "#{resource[:name]} public", points: points(row)) }
        end
      end

      # The CPU answer is the seconds spent in each mode so far, one series per mode, as the example in DigitalOcean's
      # specification shows, so the busy share is worked out between two readings.
      def cpu_points(rows)
        by_mode = rows.to_h { |row| [ row.dig("metric", "mode"), points(row).to_h ] }
        times = by_mode.values.flat_map(&:keys).uniq.sort
        times.each_cons(2).filter_map do |before, at|
          total = by_mode.values.sum { |values| values[at] && values[before] ? values[at] - values[before] : 0 }
          idle = by_mode[IDLE] && by_mode[IDLE][at] && by_mode[IDLE][before] ? by_mode[IDLE][at] - by_mode[IDLE][before] : nil
          [ at, (1 - (idle / total)) * 100 ] if idle && total.positive?
        end
      end

      def points(row)
        Array(row.to_h["values"]).filter_map do |at, value|
          number = Float(value, exception: false)
          [ Time.zone.at(at.to_i).utc, number ] if number
        end
      end

      # Several series as one line for a baseline, with instances averaged and a disk at its fullest mount.
      def combined(series, metric)
        series.flat_map(&:points).group_by(&:first).sort.map do |at, readings|
          values = readings.map(&:last)
          [ at, metric == DISK ? values.max : values.sum / values.size ]
        end
      end
    end
  end
end
