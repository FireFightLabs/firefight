module Integrations
  module Packs
    # Fly.io for one organization per environment: its apps and Managed Postgres clusters, their machines, logs,
    # metrics and releases, read with a token the workspace creates with fly tokens create. Every tool reads, except
    # the restart and rollback an admin switches on for Halon to apply fixes. Sources are cited where each is used:
    # the Machines API spec (docs.fly.io/api/machines/openapi.json), superfly/flyctl, superfly/fly-go and superfly/docs.
    class Fly < NativePack
      # The environment row's credentials, which only this pack reads.
      API_TOKEN = "api_token".freeze
      ORGANIZATION = "organization".freeze

      PROVIDER = "Fly.io".freeze
      PROVIDER_KEY = "fly".freeze
      APP = "app".freeze
      POSTGRES = "postgres".freeze
      # The addresses flyctl prints for an app and a Managed Postgres cluster (superfly/flyctl,
      # internal/command/dashboard/root.go, internal/command/deploy/deploy.go, internal/command/machine/list.go and
      # internal/command/mpg/v2/run_create.go).
      MONITORING = "monitoring".freeze
      METRICS_PAGE = "metrics".freeze
      MACHINES_PAGE = "machines".freeze

      # Fly app names are lowercase letters, digits and dashes, which is what lets one sit inside a PromQL label.
      APP_NAME = /\A[a-z0-9][a-z0-9-]*\z/
      # The machines that run an app, as flyctl counts them: platform v2, not being destroyed, and not a release
      # command or console machine (superfly/fly-go, flaps/flaps_machines.go and machine_types.go).
      PLATFORM_VERSION = "fly_platform_version".freeze
      PROCESS_GROUP = "fly_process_group".freeze
      OTHER_GROUPS = %w[fly_app_release_command fly_app_console].freeze
      GONE = %w[destroyed destroying].freeze
      STARTED = "started".freeze

      # The logs endpoint answers about 100 lines a page from a start time on, oldest first (superfly/docs,
      # monitoring/logs-api-options.mdx). This many pages are read for one call.
      LOG_LIMIT = 200
      LOG_PAGES = 10
      RELEASE_LIMIT = 20
      MACHINES_SHOWN = 20
      EVENTS_SHOWN = 3
      REGEX_TIMEOUT = 1

      # The metrics a tool takes, as PromQL over the series Fly documents (superfly/docs, monitoring/metrics.mdx).
      # %<app>s is the app's name and %<window>s the rate window. CPU is a counter of centiseconds, so a rate over it
      # divided by 100 is the CPUs in use. Memory is what is not available, in MB. Requests are per minute.
      Metric = Data.define(:title, :unit, :per_instance, :total)
      EDGE = "fly_edge_http_responses_count{app=\"%<app>s\"%<status>s}".freeze
      METRICS = {
        "cpu" => Metric.new(title: "CPU", unit: "CPUs",
                            per_instance: "sum by (instance) (rate(fly_instance_cpu{app=\"%<app>s\",mode!=\"idle\"}[%<window>s])) / 100",
                            total: "sum(rate(fly_instance_cpu{app=\"%<app>s\",mode!=\"idle\"}[%<window>s])) / 100"),
        "memory" => Metric.new(title: "Memory used", unit: "MB",
                               per_instance: "sum by (instance) (fly_instance_memory_mem_total{app=\"%<app>s\"} - fly_instance_memory_mem_available{app=\"%<app>s\"}) / 1048576",
                               total: "sum(fly_instance_memory_mem_total{app=\"%<app>s\"} - fly_instance_memory_mem_available{app=\"%<app>s\"}) / 1048576"),
        "requests" => Metric.new(title: "Requests", unit: "per minute", per_instance: nil,
                                 total: "sum(rate(#{format(EDGE, app: '%<app>s', status: '')}[%<window>s])) * 60"),
        "http_4xx" => Metric.new(title: "4xx responses", unit: "per minute", per_instance: nil,
                                 total: "sum(rate(#{format(EDGE, app: '%<app>s', status: ',status=~"4.."')}[%<window>s])) * 60"),
        "http_5xx" => Metric.new(title: "5xx responses", unit: "per minute", per_instance: nil,
                                 total: "sum(rate(#{format(EDGE, app: '%<app>s', status: ',status=~"5.."')}[%<window>s])) * 60"),
        "network_in" => Metric.new(title: "Network in", unit: "bytes/s", total: nil,
                                   per_instance: "sum by (instance) (rate(fly_instance_net_recv_bytes{app=\"%<app>s\"}[%<window>s]))"),
        "network_out" => Metric.new(title: "Network out", unit: "bytes/s", total: nil,
                                    per_instance: "sum by (instance) (rate(fly_instance_net_sent_bytes{app=\"%<app>s\"}[%<window>s]))")
      }.freeze
      DEFAULT_METRICS = %w[cpu memory requests http_5xx].freeze
      BASELINE_METRICS = %w[cpu memory requests].freeze
      POINTS = 60
      MIN_STEP = 15
      MIN_WINDOW = 60
      BASELINE_STEP = 3600

      RESOURCE = { "type" => "string", "description" => "An app or Managed Postgres cluster in the organization, by name or id, as list_resources shows it" }.freeze

      tool :list_resources,
           description: "The apps and Managed Postgres clusters in the Fly.io organization for this environment, with each one's " \
                        "status and how many machines an app has. Use it first to find the name to pass to the other tools",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :describe_resource,
           description: "How one app or Managed Postgres cluster stands now. An app: each machine's state, region, size, image, " \
                        "restart policy, health checks and their status, and its latest events, such as an exit, its code, and " \
                        "whether it ran out of memory. A cluster: its status, plan, region and the apps attached to it",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: true

      tool :search_logs,
           description: "Log lines of one app, newest first, at most #{LOG_LIMIT}, from Fly's log history of about 7 days. Fly's " \
                        "logs cannot be searched at the source, so Firefight reads the range and keeps the lines that contain " \
                        "the text, match the regular expression or leave out the excluded text",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "regex" => { "type" => "string", "description" => "Only lines matching this regular expression (optional)" },
               "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :query_metrics,
           description: "Metrics of one app over time from Fly's metrics: CPU and memory per machine, requests and 4xx and 5xx " \
                        "responses at Fly's edge per minute, and network in and out per machine. Returns min, average, max and " \
                        "latest for each, and the person sees each metric as a chart",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "metrics" => { "type" => "array", "items" => { "type" => "string", "enum" => METRICS.keys },
                              "description" => "Which metrics (optional, #{DEFAULT_METRICS.join(', ')})" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :list_deployments,
           description: "An app's releases, newest first: the version, its status (complete, failed, interrupted, running), " \
                        "what it was, who released it, when, and the image it runs. rollback_release takes the version. Use it " \
                        "to see what changed before something broke",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "limit" => { "type" => "integer", "description" => "At most this many releases (optional, #{RELEASE_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :restart_app,
           description: "Restart every running machine of an app, one at a time, for an app stuck in a bad state while its code is " \
                        "fine. Each machine reboots on the image it already runs. Stopped machines are left as they are",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: false

      tool :rollback_release,
           description: "Put every machine of an app back on the image of an earlier release, by the version list_deployments " \
                        "shows, one machine at a time, each started again before the next. A machine that changed since it was read, " \
                        "or does not start again, stops the rollback there and the rest are left as they were. The app's " \
                        "settings, secrets and fly.toml stay as they are, and Fly's release list does not show the rollback",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "release" => { "type" => "string", "description" => "The release to go back to, by its version, such as v41 or 41" }
             },
             "required" => %w[resource release]
           },
           read_only: false

      def self.credential_fields
        [
          CredentialField.new(key: API_TOKEN, label: "API token", secret: true, placeholder: "FlyV1 fm2_...",
                              hint: "A token from fly tokens create org. For Halon to only read, use fly tokens create readonly. Paste it whole, with FlyV1 in front.")
        ]
      end

      # Lists the organization's apps with the token, so a wrong token or organization is said on the form before
      # anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        token = values[API_TOKEN].to_s.strip
        organization = fields[ORGANIZATION].to_s.strip
        return "Paste an API token." if token.empty?
        return "Enter the organization's slug." if organization.empty?

        FlyApi.new(token).apps(organization, limit: 1)
        nil
      rescue FlyApi::Error => error
        Sentence.join("Fly.io refused this token or organization", error)
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_TOKEN, values[API_TOKEN].to_s.strip)
      end

      def list_resources(environment_row:, arguments:)
        rows = resources(environment_row).map do |resource|
          [ "#{resource[:name]}#{" (#{resource[:id]})" if resource[:id] != resource[:name]}", resource[:type] == APP ? "app" : "Managed Postgres cluster",
            resource[:status].presence || "status unknown", ("#{resource[:machines]} machines" if resource[:machines]) ].compact.join(", ")
        end
        organization = organization_of(environment_row)
        text = rows.empty? ? "Organization #{organization} has no apps or Managed Postgres clusters." : "Organization #{organization}, #{rows.size} apps and clusters.\n#{rows.join("\n")}"
        Telemetry.result(text, link: nil)
      end

      def describe_resource(environment_row:, arguments:)
        resource = find_resource(environment_row, arguments["resource"])
        return Telemetry.result(cluster_lines(environment_row, resource).compact.join("\n"), link: link(environment_row, resource)) if resource[:type] == POSTGRES

        machines = api(environment_row).machines(resource[:name]).select { |machine| app_machine?(machine) }
        lines = [ "#{resource[:name]}, app, status #{resource[:status].presence || 'unknown'}, #{machines.size} machines" ]
        lines << "No machines run this app, so nothing serves it." if machines.empty?
        lines.concat(machines.first(MACHINES_SHOWN).map { |machine| machine_lines(machine) })
        lines << "#{machines.size - MACHINES_SHOWN} more machines not shown." if machines.size > MACHINES_SHOWN
        Telemetry.result(lines.join("\n"), link: link(environment_row, resource, MACHINES_PAGE))
      end

      def search_logs(environment_row:, arguments:)
        resource = find_app(environment_row, arguments["resource"])
        started, ended = Capabilities::Answers.range(arguments)
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        pattern = regex(arguments["regex"])
        read, complete = read_logs(environment_row, resource, started, ended)
        lines = read.select { |line| kept?(line.text.to_s, arguments["text"], arguments["exclude"], pattern) }.sort_by(&:at).reverse
        asked = "#{resource[:name]} from #{started.utc.iso8601} to #{ended.utc.iso8601}"
        text = Telemetry.logs_text(lines.first(limit), asked: asked, limit: lines.size > limit ? limit : lines.size + 1)
        unless complete
          text = "#{text}\nFly answered more than the #{LOG_PAGES} pages Firefight reads in one call, so lines after " \
                 "#{read.last&.at&.utc&.iso8601} were not read. Narrow the range to see them."
        end
        Telemetry.result(text, link: link(environment_row, resource, MONITORING))
      end

      def query_metrics(environment_row:, arguments:)
        resource = find_app(environment_row, arguments["resource"])
        started, ended = Capabilities::Answers.range(arguments)
        asked = Array(arguments["metrics"]).map(&:to_s) & METRICS.keys
        asked = DEFAULT_METRICS if asked.empty?
        step = [ ((ended - started) / POINTS).ceil, MIN_STEP ].max
        charts = asked.map { |name| chart(environment_row, resource, name, started, ended, step) }
        Telemetry.result("#{resource[:name]}\n#{Telemetry.charts_text(charts)}", charts: charts, link: link(environment_row, resource, METRICS_PAGE))
      end

      def list_deployments(environment_row:, arguments:)
        resource = find_app(environment_row, arguments["resource"])
        releases = sorted_releases(environment_row, resource, Capabilities::Answers.limit(arguments, RELEASE_LIMIT))
        return Telemetry.result("#{resource[:name]} has no releases.", link: link(environment_row, resource)) if releases.empty?

        rows = releases.map { |release| release_line(release) }
        Telemetry.result("Latest #{rows.size} releases of #{resource[:name]}, newest first. rollback_release takes a version.\n#{rows.join("\n")}",
                         link: link(environment_row, resource))
      end

      # One restart per running machine (spec, POST /v1/apps/{app_name}/machines/{machine_id}/restart), one machine at a
      # time, so the app keeps serving from the others while each comes back.
      def restart_app(environment_row:, arguments:)
        resource = find_app(environment_row, arguments["resource"])
        machines = api(environment_row).machines(resource[:name]).select { |machine| app_machine?(machine) }
        running, stopped = machines.partition { |machine| machine["state"] == STARTED }
        fail! "No machine of #{resource[:name]} is running, so there is nothing to restart. Start its machines in Fly.io instead." if running.empty?

        said = one_at_a_time(environment_row, resource, running, "restarted") do |machine|
          api(environment_row).restart_machine(resource[:name], machine["id"])
          nil
        end
        left = stopped.any? ? "\n#{stopped.size} stopped machines were left as they are." : ""
        Telemetry.result("Restarting #{resource[:name]}, machine by machine.\n#{said.join("\n")}#{left}", link: link(environment_row, resource, MACHINES_PAGE))
      end

      # Fly documents an image change on each machine as how a machine goes back to an earlier release (superfly/docs,
      # machines/api/machines-resource.mdx). The whole config goes back with only its image changed, and current_version
      # makes Fly refuse a machine that changed since it was read, such as during a deploy.
      def rollback_release(environment_row:, arguments:)
        resource = find_app(environment_row, arguments["resource"])
        wanted = arguments["release"].to_s.strip.delete_prefix("v").delete_prefix("V")
        fail! "Say which release to go back to, by the version list_deployments shows." if wanted.empty?

        release = sorted_releases(environment_row, resource, RELEASE_LIMIT * 5).find { |each| each["version"].to_s == wanted || each["id"].to_s == wanted }
        fail! "#{resource[:name]} has no release v#{wanted} among its latest. list_deployments shows them." unless release
        image = release["imageRef"].presence
        fail! "Release v#{wanted} of #{resource[:name]} names no image, so there is nothing to go back to. Deploy it again from Fly.io instead." unless image

        machines = api(environment_row).machines(resource[:name]).select { |machine| app_machine?(machine) }
        fail! "No machine runs #{resource[:name]}, so there is nothing to roll back." if machines.empty?

        said = one_at_a_time(environment_row, resource, machines, "moved to the image") { |machine| rollback_machine(environment_row, resource, machine, image) }
        Telemetry.result("Putting #{resource[:name]} back on release v#{wanted}, image #{image}.\n#{said.join("\n")}\n" \
                         "Fly's release list does not show this, and the next deploy replaces it.", link: link(environment_row, resource, MACHINES_PAGE))
      end

      # The organization on the resource map: its apps with their machines and the hostnames their certificates cover,
      # and its Managed Postgres clusters with the apps attached to them. What could not be read for one app is a gap.
      # Each app's settings go with it as uses, its machines' plain environment by value and its secrets by name only.
      def map_of(environment_row)
        api = api(environment_row)
        organization = organization_of(environment_row)
        resources = []
        links = []
        gaps = []
        uses = []
        secrets_read = true
        listed = api.app_list(organization)
        apps = listed.items
        if listed.incomplete?
          gaps << ResourceMap::Gap.new(text: "Only the first #{apps.size} apps were read.",
                                       kinds: [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_DOMAIN ])
        end
        apps.each do |app|
          name = app["name"]
          machines = begin
            api.machines(name).select { |machine| app_machine?(machine) }
          rescue Integrations::RateLimited
            raise
          rescue FlyApi::Error => error
            gaps << ResourceMap::Gap.new(text: Sentence.join("The machines of #{name} could not be read", error), kinds: [])
            nil
          end
          found = ResourceMap::Found.new(provider: PROVIDER_KEY, account: organization, kind: ResourceMap::KIND_SERVICE, external_id: name, name: name,
                                         status: app["status"].presence, url: page(environment_row, name), details: app_details(machines))
          resources << found
          names, secrets_read = secret_names(api, name, gaps, secrets_read)
          uses.concat(ResourceMap::Use.read(from: found.key, workspace: environment_row.integration.workspace, values: machine_env(machines), names: names))
          begin
            certificates = api.certificates(name)
            certificates.items.each do |certificate|
              host = ResourceMap.domain(certificate["hostname"])
              resources << host
              links << ResourceMap::FoundLink.new(from: host.key, to: found.key, relation: ResourceMap::RELATION_SERVED_BY)
            end
            if certificates.incomplete?
              gaps << ResourceMap::Gap.new(text: "Only the first #{certificates.items.size} certificates of #{name} were read.", kinds: [ ResourceMap::KIND_DOMAIN ])
            end
          rescue Integrations::RateLimited
            raise
          rescue FlyApi::Error => error
            gaps << ResourceMap::Gap.new(text: Sentence.join("The certificates of #{name} could not be read", error), kinds: [ ResourceMap::KIND_DOMAIN ])
          end
        end
        begin
          api.postgres_clusters(organization).each do |cluster|
            found = ResourceMap::Found.new(provider: PROVIDER_KEY, account: organization, kind: ResourceMap::KIND_DATABASE, external_id: cluster["id"].to_s,
                                           name: cluster["name"].presence || cluster["id"].to_s, status: cluster["status"],
                                           url: cluster_page(environment_row, organization, cluster["id"]),
                                           details: { "type" => "Managed Postgres", "plan" => cluster["plan"], "region" => cluster["region"] }.compact)
            resources << found
            Array(cluster["attached_apps"]).each do |attached|
              next unless apps.any? { |app| app["name"] == attached["name"] }

              links << ResourceMap::FoundLink.new(from: [ PROVIDER_KEY, organization, ResourceMap::KIND_SERVICE, attached["name"] ], to: found.key,
                                                  relation: ResourceMap::RELATION_USES)
            end
          end
        rescue Integrations::RateLimited
          raise
        rescue FlyApi::Error => error
          gaps << ResourceMap::Gap.new(text: Sentence.join("Managed Postgres clusters could not be read", error), kinds: [ ResourceMap::KIND_DATABASE ])
        end
        ResourceMap::Snapshot.new(resources: resources, links: links, gaps: gaps, uses: uses)
      end

      # What normal looks like for each app: a week of CPU, memory and requests per minute, one reading an hour, for the
      # whole app. An app Fly cannot read keeps yesterday's baselines, and being asked to slow down stops the whole read.
      def baselines_of(environment_row, resources, window)
        api = api(environment_row)
        organization = organization_of(environment_row)
        resources.flat_map do |resource|
          next [] unless resource.kind == ResourceMap::KIND_SERVICE && resource.external_id.match?(APP_NAME)

          BASELINE_METRICS.filter_map do |name|
            metric = METRICS.fetch(name)
            query = format(metric.total, app: resource.external_id, window: "#{BASELINE_STEP}s")
            series = api.query_range(organization, query: query, start: window.begin, finish: window.end, step: BASELINE_STEP)
            points = series.flat_map { |each| prometheus_points(each) }.group_by(&:first).map { |at, pairs| [ at, pairs.sum(&:last) ] }.sort_by(&:first)
            ResourceMap::Baseline::Found.new(key: resource.key, metric: name, label: metric.title, unit: metric.unit, points: points) if points.any?
          end
        rescue Integrations::RateLimited
          raise
        rescue FlyApi::Error => error
          Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{error.message}")
          []
        end
      end

      def check_health!(environment_row)
        api(environment_row).apps(organization_of(environment_row), limit: 1)
      rescue FlyApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        token = ConnectionSettings.of(environment_row).credential(API_TOKEN)
        fail! "This environment has no Fly.io token. Reconnect it on the Integrations page." if token.blank?

        FlyApi.new(token)
      end

      def organization_of(environment_row) = ConnectionSettings.of(environment_row).field(ORGANIZATION) || fail!("This environment has no Fly.io organization. Reconnect it.")

      def resources(environment_row)
        @resources ||= begin
          api = api(environment_row)
          organization = organization_of(environment_row)
          apps = api.app_list(organization).items.map do |app|
            { id: app["name"], name: app["name"], type: APP, status: app["status"], machines: app["machine_count"] }
          end
          clusters = begin
            api.postgres_clusters(organization).map do |cluster|
              { id: cluster["id"].to_s, name: cluster["name"].presence || cluster["id"].to_s, type: POSTGRES, status: cluster["status"] }
            end
          rescue Integrations::RateLimited
            raise
          rescue FlyApi::Error
            []
          end
          apps + clusters
        end
      end

      def find_resource(environment_row, asked)
        fail! "Say which app or cluster, by name or id. list_resources shows them." if asked.to_s.strip.empty?

        Named.find(resources(environment_row), asked, id: :id, name: :name, provider: PROVIDER, connection: environment_row) || fail!("Nothing called #{asked} in this organization. list_resources shows what there is.")
      end

      def find_app(environment_row, asked)
        resource = find_resource(environment_row, asked)
        fail! "#{resource[:name]} is a Managed Postgres cluster, and this reads an app. describe_resource says how a cluster stands." unless resource[:type] == APP
        fail! "#{resource[:name]} is not a name Fly.io gives an app, so it cannot be read." unless resource[:name].match?(APP_NAME)

        resource
      end

      # Fly's app, the registry's site for this provider.
      def site(environment_row) = ConnectionSettings.of(environment_row).site

      def page(environment_row, app_name, *rest) = [ site(environment_row), "apps", ERB::Util.url_encode(app_name), *rest ].join("/")

      def cluster_page(environment_row, organization, cluster_id) = [ site(environment_row), "dashboard", ERB::Util.url_encode(organization), "managed_postgres", ERB::Util.url_encode(cluster_id) ].join("/")

      def link(environment_row, resource, *rest)
        url = resource[:type] == POSTGRES ? cluster_page(environment_row, organization_of(environment_row), resource[:id]) : page(environment_row, resource[:name], *rest)
        Telemetry::Link.new(provider: PROVIDER, url: url)
      end

      def app_machine?(machine)
        metadata = machine.dig("config", "metadata") || {}
        GONE.exclude?(machine["state"]) && OTHER_GROUPS.exclude?(metadata[PROCESS_GROUP]) &&
          (metadata[PLATFORM_VERSION].nil? || metadata[PLATFORM_VERSION] == "v2")
      end

      def app_details(machines)
        return {} unless machines

        images = machines.filter_map { |machine| image_of(machine) }.uniq
        { "instances" => machines.size, "region" => machines.filter_map { |machine| machine["region"] }.uniq.sort.join(", ").presence,
          "image" => (images.one? ? images.first : nil) }.compact
      end

      # The plain environment an app's machines run with, read in memory for where its settings point. The Machines API
      # gives each machine's config.env as name and value (spec, fly.MachineConfig env), and secrets are not in it.
      def machine_env(machines)
        Array(machines).each_with_object({}) do |machine, env|
          machine.dig("config", "env").to_h.each { |name, value| env[name] ||= value.to_s }
        end
      end

      # The names of an app's secrets, where a connection string such as DATABASE_URL usually is, since fly mpg attach
      # and fly postgres attach set it as one. Values are never asked for. Once Fly asks to slow down, the rest of the
      # apps' secrets are left for the next sweep, so the map's own reads go on.
      def secret_names(api, name, gaps, reading)
        return [ [], false ] unless reading

        [ api.secret_names(name), true ]
      rescue Integrations::RateLimited
        gaps << ResourceMap::Gap.new(text: "Fly.io asked Firefight to slow down, so the secret names of #{name} and the apps after it were not read.",
                                     kinds: [], settings: true)
        [ [], false ]
      rescue FlyApi::Error => error
        gaps << ResourceMap::Gap.new(text: Sentence.join("The secret names of #{name} could not be read", error), kinds: [], settings: true)
        [ [], true ]
      end

      def image_of(machine)
        ref = machine["image_ref"] || {}
        repository = [ ref["registry"], ref["repository"] ].compact.join("/")
        tagged = ref["tag"].present? ? "#{repository}:#{ref['tag']}" : repository
        tagged.presence || machine.dig("config", "image")
      end

      def machine_lines(machine)
        config = machine["config"] || {}
        guest = config["guest"] || {}
        restart = config["restart"] || {}
        checks = Array(machine["checks"]).map { |check| "#{check['name']} #{check['status']}#{": #{check['output'].to_s.squish.truncate(160)}" if check['status'] != 'passing' && check['output'].present?}" }
        events = Array(machine["events"]).sort_by { |event| -event["timestamp"].to_i }.first(EVENTS_SHOWN).map { |event| event_words(event) }
        ports = Array(config["services"]).filter_map { |service| "port #{service['internal_port']}" if service["internal_port"] }.uniq
        [
          "Machine #{machine['id']}#{" (#{machine['name']})" if machine['name'].present?}, #{machine['state']}, region #{machine['region']}" \
            "#{", group #{config.dig('metadata', PROCESS_GROUP)}" if config.dig('metadata', PROCESS_GROUP)}" \
            "#{", host #{machine['host_status']}" if machine['host_status'].present? && machine['host_status'] != 'ok'}",
          "  #{[ ("#{guest['cpus']} #{guest['cpu_kind']} CPUs" if guest['cpus']), ("#{guest['memory_mb']} MB memory" if guest['memory_mb']),
                 ("image #{image_of(machine)}" if image_of(machine)), ("restart policy #{restart['policy']}#{", up to #{restart['max_retries']} tries" if restart['max_retries']}" if restart['policy']),
                 ("listens on #{ports.join(', ')}" if ports.any?) ].compact.join(', ')}",
          ("  Checks: #{checks.to_sentence}" if checks.any?),
          ("  Latest events: #{events.to_sentence}" if events.any?)
        ].compact.join("\n")
      end

      # A machine event in words. An exit carries its code and whether it ran out of memory (superfly/fly-go,
      # machine_types.go, MachineExitEvent).
      def event_words(event)
        at = event["timestamp"] ? Time.zone.at(event["timestamp"].to_i / 1000.0).utc.iso8601 : "unknown time"
        request = event["request"].is_a?(Hash) ? event["request"] : {}
        exit_event = request["exit_event"] || request.dig("MonitorEvent", "exit_event") || {}
        detail = [ ("ran out of memory" if exit_event["oom_killed"]), ("exit code #{exit_event['exit_code']}" unless exit_event["exit_code"].nil?),
                   ("signal #{exit_event['signal']}" if exit_event["signal"].to_i.positive?), ("asked to stop" if exit_event["requested_stop"]),
                   ("restart #{request['restart_count']}" if request["restart_count"].to_i.positive?) ].compact.join(", ")
        "#{at} #{event['type']} #{event['status']}#{" (#{detail})" if detail.present?}".squish
      end

      def cluster_lines(environment_row, resource)
        cluster = api(environment_row).postgres_cluster(resource[:id])
        cluster = cluster["data"] if cluster["data"].is_a?(Hash)
        attached = Array(cluster["attached_apps"]).filter_map { |app| app["name"] }
        [
          "#{resource[:name]}, Managed Postgres cluster, status #{cluster['status'] || resource[:status]}",
          [ ("plan #{cluster['plan']}" if cluster["plan"]), ("region #{cluster['region']}" if cluster["region"]) ].compact.join(", ").presence,
          ("Attached apps: #{attached.join(', ')}" if attached.any?)
        ]
      end

      # Reads the range page by page from its start, oldest first, until a line passes its end or the pages run out.
      # Says whether the whole range was read.
      def read_logs(environment_row, resource, started, ended)
        token = (started.to_r * 1_000_000_000).to_i.to_s
        lines = []
        LOG_PAGES.times do
          answer = api(environment_row).logs(resource[:name], next_token: token)
          entries = Array(answer["data"]).filter_map { |entry| log_line(entry["attributes"] || {}) }
          return [ lines, true ] if entries.empty?

          lines.concat(entries.select { |line| line.at <= ended })
          return [ lines, true ] if entries.any? { |line| line.at > ended }

          following = answer.dig("meta", "next_token").to_s
          return [ lines, true ] if following.blank? || following == token

          token = following
        end
        [ lines, false ]
      end

      def log_line(entry)
        at = Telemetry.parse_time(entry["timestamp"])
        return nil unless at

        source = [ entry["instance"] || entry.dig("meta", "instance"), entry["region"] || entry.dig("meta", "region"), entry["level"].presence ].compact.join(" ")
        Telemetry::LogLine.new(at: at, source: source, text: entry["message"])
      end

      def regex(source)
        return nil if source.blank?

        Regexp.new(source, timeout: REGEX_TIMEOUT)
      rescue RegexpError => error
        fail! Sentence.join("The regular expression does not read", error, after: "Fix it, or search by text instead")
      end

      def kept?(text, contains, exclude, pattern)
        return false if contains.present? && !text.downcase.include?(contains.downcase)
        return false if exclude.present? && text.downcase.include?(exclude.downcase)
        return false if pattern && !pattern.match?(text)

        true
      rescue Regexp::TimeoutError
        fail! "The regular expression took too long on Fly's lines. Make it simpler, or search by text instead."
      end

      def chart(environment_row, resource, name, started, ended, step)
        metric = METRICS.fetch(name)
        expression = metric.per_instance || metric.total
        window = "#{[ step, MIN_WINDOW ].max}s"
        series = api(environment_row).query_range(organization_of(environment_row), query: format(expression, app: resource[:name], window: window),
                                                                                    start: started, finish: ended, step: step)
        drawn = series.map do |each|
          label = each.dig("metric", "instance").presence || resource[:name]
          Telemetry::Series.new(label: label, points: prometheus_points(each))
        end
        Telemetry::Chart.new(title: "#{metric.title} of #{resource[:name]}", unit: metric.unit, series: drawn, from: started, to: ended,
                             link: page(environment_row, resource[:name], METRICS_PAGE))
      end

      # Prometheus answers each point as [seconds, "value"].
      def prometheus_points(series)
        Array(series["values"]).filter_map do |at, value|
          number = Float(value, exception: false)
          [ Time.zone.at(at.to_f).utc, number ] if number&.finite?
        end
      end

      def sorted_releases(environment_row, resource, limit)
        api(environment_row).releases(resource[:name], limit: limit).sort_by { |release| -release["version"].to_i }
      end

      def release_line(release)
        who = release.dig("user", "email") || release.dig("user", "name")
        [ release["createdAt"], "v#{release['version']}", release["status"], ("stable" if release["stable"]), release["description"].presence,
          ("by #{who}" if who), ("image #{release['imageRef']}" if release["imageRef"].present?) ].compact.join(", ")
      end

      # The machine's new version, which the wait for it to start is about, or a Skipped saying why it was left alone.
      def rollback_machine(environment_row, resource, machine, image)
        config = machine["config"]
        return Skipped.new(reason: "not changed, Fly did not say how it is set up") unless config.is_a?(Hash)
        return Skipped.new(reason: "already on that image") if config["image"] == image

        updated = api(environment_row).update_machine(resource[:name], machine["id"], config: config.merge("image" => image), current_version: machine["version"])
        updated["version"]
      rescue FlyApi::Conflict
        raise FlyApi::Error, "it changed since it was read, such as during a deploy. Check it in Fly.io and run the rollback again"
      end

      # A machine left as it was on purpose, with why.
      Skipped = Data.define(:reason)

      # Changes the machines one at a time, as Fly's rolling deploys do, and waits for each to be started again before the
      # next (spec, GET .../wait). One that fails, or does not come back up, stops the rest, which are left as they were,
      # so a bad image never takes every machine down at once.
      def one_at_a_time(environment_row, resource, machines, done)
        said = []
        machines.each_with_index do |machine, index|
          where = "#{machine['id']} in #{machine['region']}"
          begin
            version = yield(machine)
            if version.is_a?(Skipped)
              said << "#{where}: #{version.reason}"
              next
            end
            if api(environment_row).wait_started(resource[:name], machine["id"], version: version)
              said << "#{where}: #{done}, started again"
              next
            end
            said << "#{where}: #{done}, but not started again within #{FlyApi::WAIT_SECONDS} seconds"
          rescue Integrations::RateLimited
            raise
          rescue FlyApi::Error => error
            said << "#{where}: not changed, #{Sentence.clean(error.message.delete_prefix('Fly answered '))}"
          end
          rest = machines.drop(index + 1)
          said << "Stopped there, so #{rest.size} more machines were left as they were. Check #{where} in Fly.io before going on." if rest.any?
          break
        end
        said
      end
    end
  end
end
