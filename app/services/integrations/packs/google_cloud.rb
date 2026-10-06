module Integrations
  module Packs
    # Google Cloud for one project per environment, read with a service account key the workspace creates: Cloud Run
    # services with their revisions, logs, metrics and errors, Cloud SQL instances, Compute Engine instances and GKE
    # clusters. Three tools change something, each as Google's own API does it, and only when the service account's roles
    # allow it and an admin switched the tool on: moving a Cloud Run service's traffic to a revision, setting its
    # instances, and restarting a Cloud SQL instance or resetting a Compute Engine instance.
    #
    # Every endpoint, parameter and field is from Google's REST references and discovery documents (Cloud Run Admin v1
    # and v2, Cloud Logging v2, Cloud Monitoring v3, Cloud SQL Admin v1, Compute Engine v1, GKE v1, Error Reporting
    # v1beta1, Resource Manager v1), and the console pages are the ones Google's own docs link to.
    class GoogleCloud < NativePack
      # The environment row's credentials, which only this pack reads.
      KEY = "service_account_key".freeze
      PROJECT = "project".freeze

      PROVIDER = "Google Cloud".freeze
      PROVIDER_KEY = "google_cloud".freeze
      # The kind of thing a resource is, kept in its details on the map.
      TYPE = "type".freeze
      TYPE_RUN = "Cloud Run service".freeze
      TYPE_SQL = "Cloud SQL instance".freeze
      TYPE_MACHINE = "Compute Engine instance".freeze
      TYPE_CLUSTER = "GKE cluster".freeze
      KINDS = {
        TYPE_RUN => ResourceMap::KIND_SERVICE, TYPE_SQL => ResourceMap::KIND_DATABASE, TYPE_MACHINE => ResourceMap::KIND_VIRTUAL_MACHINE,
        TYPE_CLUSTER => ResourceMap::KIND_CLUSTER
      }.freeze
      TYPES_BY_KIND = KINDS.invert.freeze
      SQL_STOPPED = "NEVER".freeze

      # The console pages Google's documentation links to, each opened on the connected project.
      PAGES = { TYPE_RUN => "run/services", TYPE_SQL => "sql", TYPE_MACHINE => "compute/instances", TYPE_CLUSTER => "kubernetes/list" }.freeze
      LOGS_PAGE = "logs/query".freeze
      ERRORS_PAGE = "errors".freeze

      STREAM_APP = Capabilities::STREAM_APP
      STREAM_REQUESTS = "requests".freeze
      STREAMS = [ STREAM_APP, STREAM_REQUESTS ].freeze
      RUN_REQUEST_LOG = "run.googleapis.com/requests".freeze
      # Error Reporting reads a time range as one of these periods, so the shortest that covers the range is asked.
      ERROR_PERIODS = { 60 => "PERIOD_1_HOUR", 360 => "PERIOD_6_HOURS", 1440 => "PERIOD_1_DAY", 10_080 => "PERIOD_1_WEEK" }.freeze
      READY = "Ready".freeze
      MANUAL = "MANUAL".freeze
      REVISION_TRAFFIC = "TRAFFIC_TARGET_ALLOCATION_TYPE_REVISION".freeze
      POSTGRES = "POSTGRES".freeze

      LOG_LIMIT = 200
      REVISION_LIMIT = 20
      ERROR_LIMIT = 20
      LOG_TEXT_LIMIT = 2_000

      RESOURCE = { "type" => "string", "description" => "A Cloud Run service, Cloud SQL instance, Compute Engine instance or GKE cluster, by name or id, as list_resources shows it" }.freeze
      SERVICE = { "type" => "string", "description" => "A Cloud Run service, by name or id, as list_resources shows it" }.freeze

      tool :list_resources,
           description: "The Cloud Run services, Cloud SQL instances, Compute Engine instances and GKE clusters in the Google Cloud " \
                        "project for this environment, with where each runs and how it stands. Use it first to find the name " \
                        "to pass to the other tools",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :search_logs,
           description: "Log lines from one resource, newest first, at most #{LOG_LIMIT}, from Cloud Logging. Filter by text, a " \
                        "regular expression, or text to leave out. For a Cloud Run service, stream app is what it prints and " \
                        "requests is each request it served, with status and latency",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "regex" => { "type" => "string", "description" => "Only lines matching this regular expression, case sensitive (optional)" },
               "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
               "stream" => { "type" => "string", "enum" => STREAMS, "description" => "Which logs of a Cloud Run service: app or requests (optional, app)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :query_metrics,
           description: "Metrics of one Cloud Run service, Cloud SQL instance or Compute Engine instance over time, from Cloud " \
                        "Monitoring: cpu, memory, requests, http_4xx and http_5xx for a service, cpu, memory, disk and " \
                        "tcp_connections for a database, and network_in and network_out. Returns min, average, max and " \
                        "latest, and the person sees each metric as a chart",
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

      tool :list_revisions,
           description: "A Cloud Run service's revisions, newest first: when each was made, by whom, the image it runs, whether " \
                        "it is ready, and how much of the traffic it serves. Use it to see what changed before something " \
                        "broke, and for the revision rollback_service takes",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => SERVICE,
               "limit" => { "type" => "integer", "description" => "At most this many revisions (optional, #{REVISION_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :describe_resource,
           description: "How one resource is set up and how it stands now. A Cloud Run service: its readiness, traffic split, " \
                        "image, instance limits and address. A Cloud SQL instance: its engine, state, tier, availability and " \
                        "disk. A Compute Engine instance: its state, machine type and addresses. A GKE cluster: its state, " \
                        "version and node pools",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: true

      tool :error_groups,
           description: "The errors a Cloud Run service reported to Error Reporting, grouped by kind, most frequent first, with " \
                        "how often each happened, when it was first and last seen, and a sample message",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => SERVICE,
               "text" => { "type" => "string", "description" => "Only errors whose message contains this text (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many groups (optional, #{ERROR_LIMIT})" },
               **Capabilities::RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :rollback_service,
           description: "Send all of a Cloud Run service's traffic to one of its revisions, such as the last one that worked. " \
                        "list_revisions shows them. Undo by sending the traffic back to the revision that served it before",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => SERVICE,
               "revision" => { "type" => "string", "description" => "The revision to serve all traffic, by its name as list_revisions shows it" }
             },
             "required" => %w[resource revision]
           },
           read_only: false

      tool :scale_service,
           description: "Set how many instances a Cloud Run service keeps at least (min_instances) and may start at most " \
                        "(max_instances), on the service itself, so no new revision is made. Undo by setting the values " \
                        "describe_resource showed before",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => SERVICE,
               "min_instances" => { "type" => "integer", "description" => "The fewest instances to keep running, 0 or more (optional)" },
               "max_instances" => { "type" => "integer", "description" => "The most instances it may start, 1 or more (optional)" }
             },
             "required" => [ "resource" ]
           },
           read_only: false

      tool :restart_resource,
           description: "Restart a Cloud SQL instance, which drops its connections for a short while, or reset a Compute Engine " \
                        "instance, which is a hard reset that loses what is in its memory. Cloud Run services have no restart",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: false

      def self.credential_fields
        [
          CredentialField.new(key: KEY, label: "Service account key", secret: true, multiline: true, placeholder: "{\"type\": \"service_account\", ...}",
                              hint: "The JSON key of a service account with the Viewer, Logs Viewer and Monitoring Viewer roles on the project. " \
                                    "For Halon to apply fixes, add Cloud Run Developer, Cloud SQL Editor and Compute Instance Admin.")
        ]
      end

      # Reads the project with the key, so a wrong key or project is said on the form before anything is saved. The
      # project is a connect field, whose format the registry already checked.
      def self.credential_refusal(values, region: nil, fields: {})
        key = values[KEY].to_s.strip
        project = fields[PROJECT].to_s.strip
        return "Paste the service account's JSON key." if key.empty?
        return "Enter the project id." if project.empty?

        GoogleCloudApi.new(key).project(project)
        nil
      rescue GoogleCloudApi::Error => error
        Sentence.join("Google Cloud refused this key or project", error)
      end

      # A new key drops the token minted with the one before.
      def self.store_credentials!(environment_row, values)
        settings = ConnectionSettings.of(environment_row)
        settings.store_credential!(KEY, values[KEY].to_s.strip)
        settings.store_credential!(GoogleCloudApi::TOKEN_CACHE_KEY, nil)
      end

      def list_resources(environment_row:, arguments:)
        project = project_of(environment_row)
        listing = catalog(environment_row)
        rows = listing.items.map { |item| "#{item[:name]} (#{item[:id]}), #{item[:type]} in #{item[:location]}, #{item[:status]}" }
        gaps = listing.gaps.map { |gap| "Not listed: #{gap.text}" }
        text = rows.empty? ? "Project #{project} has nothing Firefight reads." : "Project #{project}, #{rows.size} resources.\n#{rows.join("\n")}"
        Telemetry.result([ text, *gaps ].join("\n"), link: page_link(environment_row, project, TYPE_RUN))
      end

      def search_logs(environment_row:, arguments:)
        target = find(environment_row, arguments["resource"])
        stream = arguments["stream"].presence || STREAM_APP
        fail!("stream must be #{STREAMS.join(' or ')}.") unless STREAMS.include?(stream)
        fail!("Only a Cloud Run service keeps request logs. Ask for stream #{STREAM_APP}.") if stream == STREAM_REQUESTS && !target.run?

        started, ended = Capabilities::Answers.range(arguments)
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        filter = [ log_scope(environment_row, target, stream), "timestamp>=#{quote(started.utc.iso8601)}", "timestamp<=#{quote(ended.utc.iso8601)}",
                   *text_filters(arguments) ].join(" AND ")
        entries = api(environment_row).log_entries(target.project, filter, limit: limit)
        lines = entries.map { |entry| log_line(entry, ended) }
        asked = "#{target.name} (#{stream}) from #{started.utc.iso8601} to #{ended.utc.iso8601}"
        Telemetry.result(Telemetry.logs_text(lines, asked: asked, limit: limit), link: logs_link(environment_row, target))
      end

      def query_metrics(environment_row:, arguments:)
        target = find(environment_row, arguments["resource"])
        known = Metrics::BY_TYPE[target.type] || fail!("Google Cloud keeps no metrics Firefight reads for a #{target.type}. Read its logs instead.")
        asked = Array(arguments["metrics"]).map(&:to_s).uniq
        unknown = asked - known.keys
        fail!("A #{target.type} has no #{unknown.join(', ')}. It has #{known.keys.join(', ')}.") if unknown.any?

        started, ended = Capabilities::Answers.range(arguments)
        names = asked.presence || Metrics::DEFAULTS.fetch(target.type)
        alignment = alignment_for(started, ended)
        link = page_link(environment_row, target.project, target.type)
        charts = names.map do |name|
          metric = metric_for(environment_row, target, name, known)
          series = read_series(environment_row, target, metric, started, ended, alignment)
          Telemetry::Chart.new(title: "#{metric.title} of #{target.name}", unit: metric.unit, series: series, from: started, to: ended, link: link.url)
        end
        Telemetry.result("#{target.name}, a #{target.type}, every #{alignment / 60} minutes\n#{Telemetry.charts_text(charts)}", link: link, charts: charts)
      end

      def list_revisions(environment_row:, arguments:)
        target = run_target(environment_row, arguments["resource"])
        service = api(environment_row).run_service(target.project, target.location, target.name)
        revisions = api(environment_row).run_revisions(target.project, target.location, target.name, limit: Capabilities::Answers.limit(arguments, REVISION_LIMIT))
        link = page_link(environment_row, target.project, TYPE_RUN)
        return Telemetry.result("#{target.name} has no revisions.", link: link) if revisions.empty?

        shares = traffic_shares(service)
        rows = revisions.sort_by { |revision| revision["createTime"].to_s }.reverse.map { |revision| revision_line(revision, shares) }
        Telemetry.result("Latest #{rows.size} revisions of #{target.name}, newest first. rollback_service takes a revision's name.\n#{rows.join("\n")}", link: link)
      end

      def describe_resource(environment_row:, arguments:)
        target = find(environment_row, arguments["resource"])
        lines = case target.type
        when TYPE_RUN then run_lines(api(environment_row).run_service(target.project, target.location, target.name))
        when TYPE_SQL then sql_lines(api(environment_row).sql_instance(target.project, target.name))
        when TYPE_MACHINE then machine_lines(api(environment_row).compute_instance(target.project, target.location, target.name))
        when TYPE_CLUSTER then cluster_lines(api(environment_row).cluster(target.project, target.location, target.name))
        end
        Telemetry.result(lines.compact.join("\n"), link: page_link(environment_row, target.project, target.type))
      end

      def error_groups(environment_row:, arguments:)
        target = run_target(environment_row, arguments["resource"])
        started, ended = Capabilities::Answers.range(arguments)
        minutes = ((ended - started) / 60).ceil
        period = ERROR_PERIODS.find { |covers, _| covers >= minutes }&.last || ERROR_PERIODS.values.last
        limit = Capabilities::Answers.limit(arguments, ERROR_LIMIT)
        query = { "serviceFilter.service" => target.name, "timeRange.period" => period, "order" => "COUNT_DESC", "pageSize" => limit }
        groups = api(environment_row).error_group_stats(target.project, query)
        text = arguments["text"].to_s.strip.downcase
        groups = groups.select { |group| group.dig("representative", "message").to_s.downcase.include?(text) } if text.present?
        link = Telemetry::Link.new(provider: PROVIDER, url: console(environment_row, target.project, ERRORS_PAGE))
        window = period.delete_prefix("PERIOD_").downcase.tr("_", " ")
        return Telemetry.result("Error Reporting has no errors from #{target.name} in the last #{window}.", link: link) if groups.empty?

        rows = groups.first(limit).map { |group| error_line(group) }
        Telemetry.result("#{rows.size} #{'kind'.pluralize(rows.size)} of error from #{target.name} in the last #{window}, most frequent first.\n#{rows.join("\n")}", link: link)
      end

      def rollback_service(environment_row:, arguments:)
        target = run_target(environment_row, arguments["resource"])
        wanted = arguments["revision"].to_s.strip.split("/").last
        fail!("Say which revision, by its name as list_revisions shows it.") if wanted.blank?

        api = api(environment_row)
        revisions = api.run_revisions(target.project, target.location, target.name, limit: REVISION_LIMIT * 5)
        fail!("#{target.name} has no revision called #{wanted}. list_revisions shows them.") unless revisions.any? { |revision| short(revision["name"]) == wanted }

        service = api.run_service(target.project, target.location, target.name)
        before = traffic_text(service)
        # Google documents traffic as a field of the whole service, so the service goes back as it was read, with only
        # its traffic changed, which makes no new revision.
        changed = service.except("etag").merge("traffic" => [ { "type" => REVISION_TRAFFIC, "revision" => wanted, "percent" => 100 } ])
        operation = api.update_run_service(target.project, target.location, target.name, changed.merge("etag" => service["etag"]).compact)
        Telemetry.result("Google Cloud is sending all of #{target.name}'s traffic to revision #{wanted}#{operation_note(operation)}. " \
                         "Before, it went #{before}. To undo, send it back there.", link: page_link(environment_row, target.project, TYPE_RUN))
      end

      def scale_service(environment_row:, arguments:)
        target = run_target(environment_row, arguments["resource"])
        minimum = count(arguments["min_instances"], "min_instances", 0)
        maximum = count(arguments["max_instances"], "max_instances", 1)
        fail!("Give min_instances, max_instances or both.") if minimum.nil? && maximum.nil?

        api = api(environment_row)
        service = api.run_service(target.project, target.location, target.name)
        scaling = service["scaling"].to_h
        if scaling["scalingMode"] == MANUAL
          fail!("#{target.name} is set to manual scaling at #{scaling['manualInstanceCount']} instances, where minimum and maximum are not used. " \
                "Change its manual instance count in the console, or switch it back to automatic scaling.")
        end
        current_max = scaling["maxInstanceCount"]
        maximum ||= current_max.to_i if minimum && current_max.to_i.positive? && minimum > current_max.to_i
        if minimum && maximum && minimum > maximum
          fail!("min_instances (#{minimum}) cannot be above max_instances (#{maximum}). Raise max_instances too.")
        end

        wanted = { "minInstanceCount" => minimum, "maxInstanceCount" => maximum }.compact
        mask = wanted.keys.map { |field| "scaling.#{field}" }.join(",")
        operation = api.update_run_service(target.project, target.location, target.name, { "scaling" => wanted }, update_mask: mask)
        Telemetry.result("Google Cloud is setting #{target.name} to #{scaling_text(wanted)}#{operation_note(operation)}. " \
                         "Before, it was #{scaling_text(scaling)}. To undo, set those again.", link: page_link(environment_row, target.project, TYPE_RUN))
      end

      def restart_resource(environment_row:, arguments:)
        target = find(environment_row, arguments["resource"])
        api = api(environment_row)
        text = case target.type
        when TYPE_SQL
          api.restart_sql_instance(target.project, target.name)
          "Google Cloud is restarting Cloud SQL instance #{target.name}. Its connections drop until it is back, usually within a few minutes."
        when TYPE_MACHINE
          api.reset_compute_instance(target.project, target.location, target.name)
          "Google Cloud is resetting Compute Engine instance #{target.name}. It starts again from its disk, and what was in its memory is gone."
        else
          fail!("A #{target.type} has no restart in Google Cloud. For a Cloud Run service, roll back to a revision that worked, or set its instances.")
        end
        Telemetry.result("#{text} There is nothing to undo.", link: page_link(environment_row, target.project, target.type))
      end

      def check_health!(environment_row)
        api(environment_row).project(project_of(environment_row))
      rescue GoogleCloudApi::Error => error
        fail! error.message
      end

      # The project on the resource map: its Cloud Run services and the addresses they serve, Cloud SQL instances,
      # Compute Engine instances and GKE clusters. A product the key may not read, or whose API is off in the project, is
      # a gap, and nothing of its kind is taken as gone.
      def map_of(environment_row)
        project = project_of(environment_row)
        listing = catalog(environment_row)
        resources = []
        links = []
        listing.items.each do |item|
          found = ResourceMap::Found.new(provider: PROVIDER_KEY, account: project, kind: KINDS.fetch(item[:type]), external_id: item[:id], name: item[:name],
                                         status: item[:status], url: console(environment_row, project, PAGES.fetch(item[:type])), details: item[:details])
          resources << found
          item[:hosts].each do |host|
            domain = ResourceMap.domain(host)
            resources << domain
            links << ResourceMap::FoundLink.new(from: domain.key, to: found.key, relation: ResourceMap::RELATION_SERVED_BY)
          end
        end
        ResourceMap::Snapshot.new(resources: resources, links: links, gaps: listing.gaps)
      end

      # What normal looks like for each Cloud Run service, Cloud SQL instance and Compute Engine instance, read an hour at
      # a time over the window. A rate per second becomes one per minute, which a live reading can be compared with. A
      # resource Google will not read keeps yesterday's baselines, and being asked to slow down stops the whole read.
      def baselines_of(environment_row, resources, window)
        alignment = 3600
        resources.flat_map do |resource|
          target = Target.parse(resource.external_id)
          next [] unless target && Metrics::BASELINES.key?(target.type)

          Metrics::BASELINES.fetch(target.type).filter_map do |name|
            metric = metric_for(environment_row, target, name, Metrics::BY_TYPE.fetch(target.type))
            points = read_series(environment_row, target, metric, window.begin, window.end, alignment).flat_map(&:points)
            next if points.empty?

            per_minute = metric.unit == Metrics::PER_SECOND
            points = points.map { |at, value| [ at, per_minute ? value * 60 : value ] }
            ResourceMap::Baseline::Found.new(key: resource.key, metric: name, label: metric.title, unit: per_minute ? Metrics::PER_MINUTE : metric.unit, points: points)
          end
        rescue Integrations::RateLimited
          raise
        rescue GoogleCloudApi::Error => error
          Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{error.message}")
          []
        end
      end

      # What the project holds, read product by product, with what could not be read in words.
      Listing = Data.define(:items, :gaps)

      private

      def api(environment_row)
        key = ConnectionSettings.of(environment_row).credential(KEY)
        fail! "This environment has no Google Cloud key. Reconnect it on the Integrations page." if key.blank?

        @api ||= GoogleCloudApi.new(key, token_cache: ConnectionSettings.of(environment_row))
      rescue GoogleCloudApi::Error => error
        fail! Sentence.join("This environment's Google Cloud key cannot be used", error, after: "Reconnect it on the Integrations page")
      end

      def project_of(environment_row) = ConnectionSettings.of(environment_row).field(PROJECT) || fail!("This environment has no Google Cloud project. Reconnect it.")

      def catalog(environment_row)
        @catalog ||= begin
          project = project_of(environment_row)
          api = api(environment_row)
          items = []
          gaps = []
          {
            TYPE_RUN => -> { run_items(api, project) },
            TYPE_SQL => -> { whole(api.sql_instances(project)) { |instance| sql_item(project, instance) } },
            TYPE_MACHINE => -> { whole(api.compute_instances(project)) { |instance| machine_item(instance) } },
            TYPE_CLUSTER => -> { whole(api.clusters(project)) { |cluster| cluster_item(project, cluster) } }
          }.each do |type, read|
            found, complete, unreachable = read.call
            items.concat(found)
            next if complete

            text = if unreachable.present?
              "Google Cloud could not reach #{unreachable.to_sentence}, so the #{type.pluralize} there were not read."
            else
              "Only the first #{found.size} #{type.pluralize} were read."
            end
            gaps << ResourceMap::Gap.new(text: text, kinds: listed_kinds(type))
          rescue Integrations::RateLimited
            raise
          rescue GoogleCloudApi::Error => error
            gaps << ResourceMap::Gap.new(text: Sentence.join("#{type.pluralize} could not be read", error), kinds: listed_kinds(type))
          end
          Listing.new(items: items, gaps: gaps)
        end
      end

      # A list's resources as items, whether the list was read in full, and the zones Google Cloud could not reach.
      def whole(read, &) = [ read.items.map(&), read.complete, read.try(:unreachable).to_a ]

      # What a list puts on the map. A Cloud Run service also puts the run.app addresses it serves there.
      def listed_kinds(type) = [ KINDS.fetch(type), (ResourceMap::KIND_DOMAIN if type == TYPE_RUN) ].compact

      # Every region's services. A region list or a service list cut short leaves the services incomplete.
      def run_items(api, project)
        locations = api.run_locations(project)
        complete = locations.complete
        found = locations.items.filter_map { |location| location["locationId"] }.flat_map do |location|
          services = api.run_services(project, location)
          complete &&= services.complete
          services.items.map { |service| run_item(service) }
        end
        [ found, complete ]
      end

      # Each kind's labels are where Google's API puts them: labels on a Cloud Run service and a Compute Engine instance,
      # settings.userLabels on a Cloud SQL instance and resourceLabels on a GKE cluster.
      def run_item(service)
        target = Target.parse(service["name"])
        container = Array(service.dig("template", "containers")).first.to_h
        hosts = Array(service["urls"]).push(service["uri"]).compact.filter_map { |url| host_of(url) }.uniq
        { type: TYPE_RUN, id: service["name"], name: target&.name || service["name"], location: target&.location, status: run_status(service), hosts: hosts,
          details: { TYPE => TYPE_RUN, "region" => target&.location, "image" => container["image"],
                     "latest_revision" => short(service["latestReadyRevision"]), ResourceMap::TAGS => service["labels"].presence }.compact }
      end

      def host_of(url)
        URI.parse(url).host
      rescue URI::InvalidURIError
        nil
      end

      # A stopped instance still reports RUNNABLE, and only its activation policy NEVER says it is stopped (Cloud SQL,
      # Start, stop, and restart instances).
      def sql_item(project, instance)
        status = instance.dig("settings", "activationPolicy") == SQL_STOPPED ? "stopped" : instance["state"].to_s.downcase
        { type: TYPE_SQL, id: instance["connectionName"].presence || "#{project}:#{instance['region']}:#{instance['name']}", name: instance["name"],
          location: instance["region"], status: status, hosts: [],
          details: { TYPE => TYPE_SQL, "engine" => instance["databaseVersion"], "tier" => instance.dig("settings", "tier"),
                     "availability" => instance.dig("settings", "availabilityType"), "region" => instance["region"],
                     ResourceMap::TAGS => instance.dig("settings", "userLabels").presence }.compact }
      end

      def machine_item(instance)
        path = URI.parse(instance["selfLink"].to_s).path.to_s[%r{projects/.+\z}]
        zone = instance["zone"].to_s.split("/").last
        { type: TYPE_MACHINE, id: path, name: instance["name"], location: zone, status: instance["status"].to_s.downcase, hosts: [],
          details: { TYPE => TYPE_MACHINE, "zone" => zone, "machine_type" => instance["machineType"].to_s.split("/").last,
                     ResourceMap::TAGS => instance["labels"].presence }.compact }
      end

      def cluster_item(project, cluster)
        { type: TYPE_CLUSTER, id: "projects/#{project}/locations/#{cluster['location']}/clusters/#{cluster['name']}", name: cluster["name"],
          location: cluster["location"], status: cluster["status"].to_s.downcase, hosts: [],
          details: { TYPE => TYPE_CLUSTER, "location" => cluster["location"], "version" => cluster["currentMasterVersion"],
                     "node_pools" => Array(cluster["nodePools"]).size, "autopilot" => cluster.dig("autopilot", "enabled"),
                     ResourceMap::TAGS => cluster["resourceLabels"].presence }.compact }
      end

      def run_status(service)
        state = service.dig("terminalCondition", "state").to_s
        return "reconciling" if service["reconciling"]

        { "CONDITION_SUCCEEDED" => "ready", "CONDITION_FAILED" => "failed", "CONDITION_RECONCILING" => "reconciling",
          "CONDITION_PENDING" => "pending" }.fetch(state, state.downcase.presence || "unknown")
      end

      # A resource by its id, or by its name from the map's last sweep and then the project's live list. Only the
      # connected project is reached, whatever id is given.
      def find(environment_row, asked)
        wanted = asked.to_s.strip
        fail! "Say which resource, by name or id. list_resources shows them." if wanted.empty?

        target = Target.parse(wanted) || named(environment_row, wanted)
        fail!("Nothing called #{wanted} in this project. list_resources shows what there is.") unless target
        fail!("#{wanted} is in project #{target.project}, and this connection reaches #{project_of(environment_row)}.") if target.project != project_of(environment_row)

        target
      end

      # By its name on the map's last sweep, then in the live list. A name two resources share is refused with their ids.
      def named(environment_row, wanted)
        mapped = ResourceMap::Resource.present.where(integration_environment: environment_row).pluck(:external_id, :name).map { |id, name| { id: id, name: name } }
        found = Named.find(mapped, wanted, id: :id, name: :name, provider: PROVIDER, connection: environment_row) ||
                Named.find(catalog(environment_row).items, wanted, id: :id, name: :name, provider: PROVIDER, connection: environment_row)
        found && Target.parse(found[:id])
      end

      def run_target(environment_row, asked)
        target = find(environment_row, asked)
        fail!("#{target.name} is a #{target.type}. This works on a Cloud Run service.") unless target.run?

        target
      end

      def count(value, name, least)
        return nil if value.nil? || value.to_s.strip.empty?

        number = Integer(value, exception: false)
        fail!("#{name} must be a whole number, #{least} or more.") unless number && number >= least
        number
      end

      # The Logging query that selects a resource's logs, by the monitored resource type and labels Google documents for it.
      def log_scope(environment_row, target, stream)
        case target.type
        when TYPE_RUN
          requests = "log_id(#{quote(RUN_REQUEST_LOG)})"
          "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=#{quote(target.name)} AND " \
            "resource.labels.location=#{quote(target.location)} AND #{stream == STREAM_REQUESTS ? requests : "NOT #{requests}"}"
        when TYPE_SQL then "resource.type=\"cloudsql_database\" AND resource.labels.database_id=#{quote("#{target.project}:#{target.name}")}"
        when TYPE_MACHINE
          id = api(environment_row).compute_instance(target.project, target.location, target.name)["id"]
          "resource.type=\"gce_instance\" AND resource.labels.instance_id=#{quote(id)}"
        when TYPE_CLUSTER then "resource.labels.cluster_name=#{quote(target.name)} AND resource.labels.location=#{quote(target.location)}"
        end
      end

      def text_filters(arguments)
        [
          ("SEARCH(#{quote(arguments['text'])})" if arguments["text"].present?),
          ("textPayload=~#{quote(arguments['regex'])}" if arguments["regex"].present?),
          ("NOT SEARCH(#{quote(arguments['exclude'])})" if arguments["exclude"].present?)
        ].compact
      end

      # A string in Logging's and Monitoring's query languages, quoted and escaped, so a value never becomes part of the query.
      def quote(value) = "\"#{value.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}\""

      def log_line(entry, fallback)
        at = Telemetry.parse_time(entry["timestamp"]) || fallback
        labels = entry.dig("resource", "labels").to_h
        source = labels["revision_name"] || labels["pod_name"] || labels["instance_id"] || labels["database_id"] || entry["logName"].to_s.split("/").last
        severity = entry["severity"].presence_in(%w[WARNING ERROR CRITICAL ALERT EMERGENCY])
        Telemetry::LogLine.new(at: at, source: [ source, severity ].compact.join(" "), text: log_text(entry))
      end

      def log_text(entry)
        request = entry["httpRequest"]
        return [ request["requestMethod"], request["requestUrl"], request["status"], request["latency"] ].compact.join(" ") if request.present? && entry["textPayload"].blank?
        return entry["textPayload"] if entry["textPayload"].present?

        payload = entry["jsonPayload"].presence || entry["protoPayload"].to_h.slice("methodName", "resourceName", "status").presence
        message = payload.is_a?(Hash) ? payload["message"].presence || payload.to_json : payload.to_s
        message.to_s.truncate(LOG_TEXT_LIMIT)
      end

      # Cloud Run's own address for a revision's logs, which its API gives, or the Logs Explorer of the project.
      def logs_link(environment_row, target)
        if target.run?
          service = api(environment_row).run_service(target.project, target.location, target.name)
          revision = service["latestReadyRevision"].presence
          uri = api(environment_row).get("#{GoogleCloudApi::RUN}/#{revision}")["logUri"] if revision
          return Telemetry::Link.new(provider: PROVIDER, url: uri) if uri.present?
        end
        Telemetry::Link.new(provider: PROVIDER, url: console(environment_row, target.project, LOGS_PAGE))
      rescue GoogleCloudApi::Error
        Telemetry::Link.new(provider: PROVIDER, url: console(environment_row, target.project, LOGS_PAGE))
      end

      def page_link(environment_row, project, type) = Telemetry::Link.new(provider: PROVIDER, url: console(environment_row, project, PAGES.fetch(type)))

      # The console is the registry's site for Google Cloud.
      def console(environment_row, project, page) = "#{ConnectionSettings.of(environment_row).site}/#{page}?#{{ "project" => project }.to_query}"

      # A Cloud SQL instance's connections are read by its engine's own metric.
      def metric_for(environment_row, target, name, known)
        return known.fetch(name) unless target.type == TYPE_SQL && name == "tcp_connections"

        engine = api(environment_row).sql_instance(target.project, target.name)["databaseVersion"].to_s
        engine.start_with?(POSTGRES) ? Metrics::POSTGRES_CONNECTIONS : Metrics::SQL_CONNECTIONS
      end

      def read_series(environment_row, target, metric, started, ended, alignment)
        filter = [ "metric.type=#{quote(metric.type)}", metric_scope(target), metric.filter ].compact.join(" AND ")
        query = { "filter" => filter, "interval.startTime" => started.utc.iso8601, "interval.endTime" => ended.utc.iso8601,
                  "aggregation.alignmentPeriod" => "#{alignment}s", "aggregation.perSeriesAligner" => metric.aligner,
                  "aggregation.crossSeriesReducer" => metric.reducer, "view" => "FULL" }
        api(environment_row).time_series(target.project, query).map do |series|
          points = Array(series["points"]).filter_map do |point|
            at = Telemetry.parse_time(point.dig("interval", "endTime"))
            value = point.dig("value", "doubleValue") || point.dig("value", "int64Value")
            [ at, value.to_f * metric.scale ] if at && !value.nil?
          end
          label = series.dig("resource", "labels", "revision_name") || series.dig("metric", "labels", "database") || target.name
          Telemetry::Series.new(label: metric.reducer ? target.name : label, points: points.sort_by(&:first))
        end
      end

      # The monitored resource a metric is read from, by the type and labels Google's resource list gives for it.
      def metric_scope(target)
        case target.type
        when TYPE_RUN
          "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=#{quote(target.name)} AND resource.labels.location=#{quote(target.location)}"
        when TYPE_SQL then "resource.type=\"cloudsql_database\" AND resource.labels.database_id=#{quote("#{target.project}:#{target.name}")}"
        when TYPE_MACHINE then "resource.type=\"gce_instance\" AND resource.labels.zone=#{quote(target.location)} AND metric.labels.instance_name=#{quote(target.name)}"
        end
      end

      def alignment_for(started, ended)
        seconds = ((ended - started) / Metrics::POINTS).ceil
        [ ((seconds + 59) / 60) * 60, Metrics::MIN_ALIGNMENT ].max
      end

      def short(name) = name.to_s.split("/").last

      # Each revision's share of the traffic, from what Cloud Run reports it serves, the latest revision named by type.
      def traffic_shares(service)
        Array(service["trafficStatuses"].presence || service["traffic"]).each_with_object(Hash.new(0)) do |share, shares|
          revision = share["revision"].presence || short(service["latestReadyRevision"])
          shares[short(revision)] += share["percent"].to_i
        end
      end

      def traffic_text(service)
        shares = traffic_shares(service).select { |_, percent| percent.positive? }
        shares.any? ? shares.map { |revision, percent| "#{percent}% to #{revision}" }.join(", ") : "to the latest ready revision"
      end

      def revision_line(revision, shares)
        ready = Array(revision["conditions"]).find { |condition| condition["type"] == READY }
        state = ready ? ready["state"].to_s.delete_prefix("CONDITION_").downcase : "unknown"
        image = Array(revision["containers"]).filter_map { |container| container["image"] }.join(", ")
        [ revision["createTime"], short(revision["name"]), ("by #{revision['creator']}" if revision["creator"]), "image #{image}",
          "ready #{state}", "#{shares[short(revision['name'])]}% of traffic" ].compact.join(", ")
      end

      def error_line(group)
        message = group.dig("representative", "message").to_s.lines.first.to_s.strip.truncate(300)
        status = group.dig("group", "resolutionStatus").to_s.downcase.presence
        [ "#{group['count']} times", ("#{group['affectedUsersCount']} users" if group["affectedUsersCount"].to_i.positive?),
          "first #{group['firstSeenTime']}", "last #{group['lastSeenTime']}", status, message ].compact.join(", ")
      end

      def scaling_text(scaling)
        least = scaling["minInstanceCount"].to_i
        [ ("at least #{least} #{'instance'.pluralize(least)}" if scaling.key?("minInstanceCount") || !scaling.key?("maxInstanceCount")),
          ("at most #{scaling['maxInstanceCount']}" if scaling["maxInstanceCount"]) ].compact.join(" and ")
      end

      def operation_note(operation)
        operation["name"].present? ? " as operation #{short(operation['name'])}" : ""
      end

      def run_lines(service)
        container = Array(service.dig("template", "containers")).first.to_h
        scaling = service["scaling"].to_h
        revision_scaling = service.dig("template", "scaling").to_h
        condition = service["terminalCondition"].to_h
        [
          "#{short(service['name'])}, a Cloud Run service, #{run_status(service)}#{": #{condition['message']}" if condition['message'].present?}",
          "Traffic: #{traffic_text(service)}. Latest ready revision #{short(service['latestReadyRevision'])}, latest made #{short(service['latestCreatedRevision'])}.",
          "Runs #{container['image']}",
          ("Scaling: #{scaling['scalingMode'] == MANUAL ? "manual, #{scaling['manualInstanceCount']} instances" : scaling_text(scaling)} on the service, " \
           "revision limits #{scaling_text(revision_scaling)}" if scaling.any? || revision_scaling.any?),
          ("Resources: #{container.dig('resources', 'limits').to_h.map { |name, value| "#{name} #{value}" }.join(', ')}" if container.dig("resources", "limits").present?),
          ("Address: #{service['uri']}" if service["uri"]),
          "Last changed #{service['updateTime']} by #{service['lastModifier'] || 'unknown'}"
        ]
      end

      def sql_lines(instance)
        settings = instance["settings"].to_h
        [
          "#{instance['name']}, a Cloud SQL #{instance['databaseVersion']} instance in #{instance['region']}, #{instance['state'].to_s.downcase}",
          "Tier #{settings['tier']}, #{settings['availabilityType'].to_s.downcase} availability, activation #{settings['activationPolicy'].to_s.downcase}" \
          "#{", edition #{settings['edition'].to_s.downcase}" if settings['edition']}",
          ("Disk #{settings['dataDiskSizeGb']} GB" if settings["dataDiskSizeGb"]),
          ("Replica of #{instance['masterInstanceName']}" if instance["masterInstanceName"]),
          ("Addresses: #{Array(instance['ipAddresses']).map { |address| "#{address['ipAddress']} (#{address['type'].to_s.downcase})" }.join(', ')}" if instance["ipAddresses"].present?)
        ]
      end

      def machine_lines(instance)
        addresses = Array(instance["networkInterfaces"]).flat_map do |interface|
          [ interface["networkIP"], *Array(interface["accessConfigs"]).filter_map { |config| config["natIP"] } ]
        end.compact
        [
          "#{instance['name']}, a Compute Engine instance in #{instance['zone'].to_s.split('/').last}, #{instance['status'].to_s.downcase}" \
          "#{": #{instance['statusMessage']}" if instance['statusMessage'].present?}",
          "Machine type #{instance['machineType'].to_s.split('/').last}",
          ("Started #{instance['lastStartTimestamp']}" if instance["lastStartTimestamp"]),
          ("Addresses: #{addresses.join(', ')}" if addresses.any?)
        ]
      end

      def cluster_lines(cluster)
        pools = Array(cluster["nodePools"]).map do |pool|
          autoscaling = pool["autoscaling"].to_h
          size = autoscaling["enabled"] ? "autoscaling #{autoscaling['minNodeCount'] || autoscaling['totalMinNodeCount']} to #{autoscaling['maxNodeCount'] || autoscaling['totalMaxNodeCount']} nodes" : "#{pool['initialNodeCount']} nodes per zone"
          "#{pool['name']}: #{pool['status'].to_s.downcase}, #{pool.dig('config', 'machineType')}, #{size}, version #{pool['version']}"
        end
        [
          "#{cluster['name']}, a GKE#{' Autopilot' if cluster.dig('autopilot', 'enabled')} cluster in #{cluster['location']}, #{cluster['status'].to_s.downcase}",
          "Control plane version #{cluster['currentMasterVersion']}",
          ("Node pools:\n#{pools.join("\n")}" if pools.any?),
          "Its workloads are read through Kubernetes, which this connection does not reach. Its logs are here."
        ]
      end
    end
  end
end
