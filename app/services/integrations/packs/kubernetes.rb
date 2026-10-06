module Integrations
  module Packs
    # Reads the workloads in one or more namespaces of a cluster with a service account token the team creates, with
    # their pods' logs, current usage, rollout history and events. rollout_undo, rollout_restart and scale_workload change
    # a workload as kubectl rollout undo, rollout restart and scale do, when the token's role allows it and an admin
    # switched them on. Paths and fields follow the Kubernetes API reference. The changes follow kubectl's own source in
    # kubernetes/kubectl, pkg/polymorphichelpers, files rollback.go, objectrestarter.go and history.go.
    class Kubernetes < NativePack
      # The secrets this pack keeps on the environment row, and the connect fields the registry asks beside them.
      TOKEN = "token".freeze
      CA = "ca".freeze
      SERVER = "server".freeze
      NAMESPACES = "namespaces".freeze
      ALL_NAMESPACES = "*".freeze
      NAMESPACE_FORMAT = /\A[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?\z/

      PROVIDER = "Kubernetes".freeze
      PROVIDER_KEY = KubernetesApi::PROVIDER_KEY

      # What a workload is, where the API keeps it, and what it is on the resource map.
      Kind = Data.define(:key, :name, :plural, :api, :map_kind, :aliases)
      DEPLOYMENT = "deployment".freeze
      STATEFULSET = "statefulset".freeze
      DAEMONSET = "daemonset".freeze
      CRONJOB = "cronjob".freeze
      JOB = "job".freeze
      APPS = "/apis/apps/v1".freeze
      BATCH = "/apis/batch/v1".freeze
      CORE = "/api/v1".freeze
      NETWORKING = "/apis/networking.k8s.io/v1".freeze
      METRICS_API = "/apis/metrics.k8s.io/v1beta1".freeze
      AUTOSCALING = "/apis/autoscaling/v2".freeze
      WORKLOADS = [
        Kind.new(key: DEPLOYMENT, name: "Deployment", plural: "deployments", api: APPS, map_kind: ResourceMap::KIND_SERVICE, aliases: %w[deployments deploy]),
        Kind.new(key: STATEFULSET, name: "StatefulSet", plural: "statefulsets", api: APPS, map_kind: ResourceMap::KIND_SERVICE, aliases: %w[statefulsets sts]),
        Kind.new(key: DAEMONSET, name: "DaemonSet", plural: "daemonsets", api: APPS, map_kind: ResourceMap::KIND_SERVICE, aliases: %w[daemonsets ds]),
        Kind.new(key: CRONJOB, name: "CronJob", plural: "cronjobs", api: BATCH, map_kind: ResourceMap::KIND_JOB, aliases: %w[cronjobs cj]),
        Kind.new(key: JOB, name: "Job", plural: "jobs", api: BATCH, map_kind: ResourceMap::KIND_JOB, aliases: %w[jobs])
      ].index_by(&:key).freeze
      ROLLING = [ DEPLOYMENT, STATEFULSET, DAEMONSET ].freeze
      SCALABLE = [ DEPLOYMENT, STATEFULSET ].freeze
      SERVICE = Kind.new(key: "service", name: "Service", plural: "services", api: CORE, map_kind: ResourceMap::KIND_LOAD_BALANCER, aliases: %w[services svc])
      INGRESS = Kind.new(key: "ingress", name: "Ingress", plural: "ingresses", api: NETWORKING, map_kind: ResourceMap::KIND_LOAD_BALANCER, aliases: %w[ingresses ing])

      # kubectl's annotations and labels, from k8s.io/api and kubectl's deployment util.
      REVISION = "deployment.kubernetes.io/revision".freeze
      CHANGE_CAUSE = "kubernetes.io/change-cause".freeze
      RESTARTED_AT = "kubectl.kubernetes.io/restartedAt".freeze
      POD_TEMPLATE_HASH = "pod-template-hash".freeze
      # What kubectl rollout undo keeps from the deployment rather than taking from the replica set it goes back to.
      ANNOTATIONS_KEPT = %w[
        kubectl.kubernetes.io/last-applied-configuration deployment.kubernetes.io/revision deployment.kubernetes.io/revision-history
        deployment.kubernetes.io/desired-replicas deployment.kubernetes.io/max-replicas deprecated.deployment.rollback.to
      ].freeze

      LOG_LIMIT = 200
      # Lines read per container before filtering, since the API server cannot search a log.
      LOG_FETCH = 1_000
      LOG_BYTES = 2_000_000
      POD_LIMIT = 10
      LOG_READS = 20
      PODS_SHOWN = 20
      EVENTS_SHOWN = 15
      EVENT_LIMIT = 50
      HISTORY_LIMIT = 10
      JOBS_SHOWN = 5
      LISTED_LIMIT = 300
      REGEX_TIMEOUT = 1.0
      # A quantity's suffix, as the API writes CPU and memory.
      SUFFIXES = {
        "n" => 1e-9, "u" => 1e-6, "m" => 1e-3, "" => 1, "k" => 1e3, "M" => 1e6, "G" => 1e9, "T" => 1e12, "P" => 1e15, "E" => 1e18,
        "Ki" => 1024, "Mi" => 1024**2, "Gi" => 1024**3, "Ti" => 1024**4, "Pi" => 1024**5, "Ei" => 1024**6
      }.freeze
      QUANTITY = /\A([+-]?[0-9.]+(?:[eE][+-]?[0-9]+)?)(Ki|Mi|Gi|Ti|Pi|Ei|n|u|m|k|M|G|T|P|E)?\z/
      MIB = 1024**2
      EVENT_WARNING = "Warning".freeze
      EVENTS_ALL = "all".freeze
      EVENT_TYPES = [ EVENT_WARNING, "Normal", EVENTS_ALL ].freeze
      # Kubernetes has no page of its own for a result, so each answer names the kubectl command that shows the same.
      CHECK_LINE = "There is no Kubernetes page to link to. To check this at the source, run: %<command>s".freeze

      NAMESPACE = { "type" => "string", "description" => "The namespace (optional when the connection reaches one namespace)" }.freeze
      RESOURCE = { "type" => "string", "description" => "A workload as kind/name, such as deployment/web, statefulset/db, daemonset/agent, cronjob/nightly or job/migrate, or a name alone when only one workload has it" }.freeze

      tool :list_resources,
           description: "The workloads (deployments, statefulsets, daemonsets, cronjobs and jobs), services and ingresses in the " \
                        "connected namespaces, with how many pods are ready and whether each is running, progressing or failed. " \
                        "Use it first to find the kind/name to pass to the other tools",
           params_schema: { "type" => "object", "properties" => { "namespace" => { "type" => "string", "description" => "Only this namespace (optional)" } } },
           read_only: true

      tool :workload_logs,
           description: "What a workload's pods printed, newest first, at most #{LOG_LIMIT} lines, from its #{POD_LIMIT} newest pods. " \
                        "Filter by text or a regular expression. previous reads each container as it was before its last " \
                        "restart, which is where a crash's last lines are. Kubernetes keeps logs only for pods that still exist",
           params_schema: {
             "type" => "object",
             "properties" => {
               "namespace" => NAMESPACE, "resource" => RESOURCE,
               "pod" => { "type" => "string", "description" => "One pod by name instead of a workload's pods (optional)" },
               "container" => { "type" => "string", "description" => "Only this container (optional, every container)" },
               "previous" => { "type" => "boolean", "description" => "Read each container before its last restart (optional)" },
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "regex" => { "type" => "string", "description" => "Only lines matching this regular expression (optional)" },
               "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **Capabilities::RANGE
             }
           },
           read_only: true

      tool :pod_metrics,
           description: "CPU and memory each pod of a workload uses now, against its requests and limits, from the cluster's " \
                        "metrics API. The metrics API keeps only the latest reading, so this is never a history",
           params_schema: { "type" => "object", "properties" => { "namespace" => NAMESPACE, "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: true

      tool :describe_workload,
           description: "How one workload stands now: desired, ready and updated replicas, its conditions, what each container " \
                        "runs with its requests, limits and probes, each pod's phase, restarts and why its containers last " \
                        "stopped (such as OOMKilled or CrashLoopBackOff), and its latest events. A cronjob shows its schedule and recent jobs",
           params_schema: { "type" => "object", "properties" => { "namespace" => NAMESPACE, "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: true

      tool :rollout_history,
           description: "The revisions of a deployment, statefulset or daemonset, newest first: when each was made, the images " \
                        "it ran and its change cause, and which one is current. rollout_undo takes the revision number",
           params_schema: {
             "type" => "object",
             "properties" => {
               "namespace" => NAMESPACE, "resource" => RESOURCE,
               "limit" => { "type" => "integer", "description" => "At most this many revisions (optional, #{HISTORY_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :list_events,
           description: "Events in a namespace, newest first: scheduling failures, failed probes, image pulls, evictions, " \
                        "out of memory kills and the rest. The API server keeps events for an hour by default",
           params_schema: {
             "type" => "object",
             "properties" => {
               "namespace" => NAMESPACE,
               "resource" => { "type" => "string", "description" => "Only events about objects whose name starts with this, such as a workload's name, which also matches its pods (optional)" },
               "type" => { "type" => "string", "enum" => EVENT_TYPES, "description" => "Warning, Normal or all (optional, Warning)" },
               "limit" => { "type" => "integer", "description" => "At most this many events (optional, #{EVENT_LIMIT})" }
             }
           },
           read_only: true

      tool :rollout_undo,
           description: "Put a deployment, statefulset or daemonset back on an earlier revision from rollout_history, as kubectl " \
                        "rollout undo does. The pods roll out again as the workload's strategy says",
           params_schema: {
             "type" => "object",
             "properties" => {
               "namespace" => NAMESPACE, "resource" => RESOURCE,
               "revision" => { "type" => "integer", "description" => "The revision to go back to, as rollout_history shows it" }
             },
             "required" => %w[resource revision]
           },
           read_only: false

      tool :rollout_restart,
           description: "Replace every pod of a deployment, statefulset or daemonset with a fresh one, as kubectl rollout restart " \
                        "does, following the workload's strategy so it keeps serving",
           params_schema: { "type" => "object", "properties" => { "namespace" => NAMESPACE, "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: false

      tool :scale_workload,
           description: "Set how many pods a deployment or statefulset runs, as kubectl scale does",
           params_schema: {
             "type" => "object",
             "properties" => {
               "namespace" => NAMESPACE, "resource" => RESOURCE,
               "replicas" => { "type" => "integer", "description" => "How many pods to run, 0 or more" }
             },
             "required" => %w[resource replicas]
           },
           read_only: false

      def self.credential_fields
        [
          CredentialField.new(key: TOKEN, label: "Service account token", secret: true, placeholder: "eyJhbGciOi...",
                              hint: "The token of a service account whose role can get and list workloads, replica sets, controller revisions, pods, pod logs, services, ingresses, events and pod metrics. For Halon to apply fixes, its role also needs patch on deployments, statefulsets, daemonsets and their scale."),
          CredentialField.new(key: CA, label: "CA certificate", secret: false, multiline: true, placeholder: "LS0tLS1CRUdJTi...",
                              hint: "The certificate-authority-data from your kubeconfig, or the cluster's CA in PEM. Firefight trusts only this CA for this cluster.")
        ]
      end

      # Lists deployments in each namespace with the token, so the form names a wrong address, CA, token or namespace
      # before anything is saved. The registry has already checked the address and namespaces against their patterns.
      def self.credential_refusal(values, region: nil, fields: {})
        token, ca = values.values_at(TOKEN, CA).map { |value| value.to_s.strip }
        server = fields[SERVER].to_s.strip
        return "Enter the API server address." if server.empty?
        return "Paste a service account token." if token.empty?
        return "Paste the cluster's CA certificate." if ca.empty?

        namespaces = namespace_list(fields[NAMESPACES])
        return "Enter the namespaces, or * for every namespace." if namespaces.empty?

        refusal = KubernetesApi.refusal(server, ca)
        return refusal if refusal

        probe(KubernetesApi.new(server: server, token: token, ca: ca), namespaces)
        nil
      rescue KubernetesApi::Error => error
        Sentence.all("The cluster refused this connection.", error)
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(TOKEN, values[TOKEN].to_s.strip)
        environment_row.store_credential!(CA, values[CA].to_s.strip)
      end

      # The namespaces field holds names separated by commas, which the registry's pattern has checked.
      def self.namespace_list(value) = value.to_s.split(",").map(&:strip).compact_blank.uniq

      # One deployment listed in each namespace, which needs the token, its role and the namespace to all be right.
      def self.probe(api, namespaces)
        namespaces.each { |namespace| api.get(collection(WORKLOADS.fetch(DEPLOYMENT), namespace), "limit" => 1) }
      end

      def self.collection(kind, namespace)
        namespace == ALL_NAMESPACES ? "#{kind.api}/#{kind.plural}" : "#{kind.api}/namespaces/#{segment(namespace)}/#{kind.plural}"
      end

      def self.segment(value) = Http.segment(value)

      def check_health!(environment_row)
        self.class.probe(api(environment_row), connected(environment_row))
      rescue KubernetesApi::Error => error
        fail! error.message
      end

      def list_resources(environment_row:, arguments:)
        scope = arguments["namespace"].present? ? [ namespace_for(environment_row, arguments["namespace"]) ] : connected(environment_row)
        lines = []
        notes = []
        scope.each do |namespace|
          WORKLOADS.each_value do |kind|
            items, note = listed(environment_row, kind, namespace)
            notes << note if note
            items.reject { |item| kind.key == JOB && owned_by?(item, CRONJOB) }.each { |item| lines << workload_line(kind, item) }
          end
          [ SERVICE, INGRESS ].each do |kind|
            items, note = listed(environment_row, kind, namespace)
            notes << note if note
            items.each { |item| lines << network_line(kind, item) }
          end
        end
        where = scope == [ ALL_NAMESPACES ] ? "every namespace" : scope.join(", ")
        command = "kubectl get #{[ *WORKLOADS.values, SERVICE, INGRESS ].map(&:plural).join(',')} #{scope == [ ALL_NAMESPACES ] ? '--all-namespaces' : "-n #{scope.join(' ')}"}"
        return answer([ "Nothing found in #{where}.", *notes ].join("\n"), command) if lines.empty?

        shown = lines.first(LISTED_LIMIT)
        cut = lines.size > LISTED_LIMIT ? " Only the first #{LISTED_LIMIT} are shown, so name a namespace to see the rest." : ""
        answer([ "#{lines.size} resources in #{where}.#{cut}", *shown, *notes ].join("\n"), command)
      end

      def workload_logs(environment_row:, arguments:)
        started, ended = Capabilities::Answers.range(arguments)
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        matcher = line_matcher(arguments)
        namespace, pods, asked, target = log_pods(environment_row, arguments)
        notes = []
        notes << "Only the newest #{POD_LIMIT} of #{pods.size} pods were read." if pods.size > POD_LIMIT
        reads = pods.first(POD_LIMIT).flat_map do |pod|
          names = Array(pod.dig("spec", "containers")).map { |container| container["name"] }
          names &= [ arguments["container"] ] if arguments["container"].present?
          names.map { |container| [ pod.dig("metadata", "name"), container ] }
        end
        fail! "No pod here has a container called #{arguments['container']}." if reads.empty? && arguments["container"].present? && pods.any?
        notes << "Only #{LOG_READS} of #{reads.size} containers were read." if reads.size > LOG_READS
        lines = reads.first(LOG_READS).flat_map do |pod, container|
          container_lines(environment_row, namespace, pod, container, started, ended, arguments["previous"] == true, matcher)
        rescue KubernetesApi::NotFound, KubernetesApi::Forbidden => error
          notes << Sentence.join("#{pod}/#{container}", error)
          []
        rescue KubernetesApi::Error => error
          raise unless arguments["previous"] == true

          notes << Sentence.join("#{pod}/#{container} has no earlier container to read", error)
          []
        end
        shown = lines.sort_by { |line| -line.at.to_f }.first(limit)
        text = Telemetry.logs_text(shown, asked: "#{asked} from #{started.utc.iso8601} to #{ended.utc.iso8601}", limit: limit)
        command = "kubectl logs #{target} -n #{namespace} --timestamps --since-time=#{started.utc.iso8601}#{" -c #{arguments['container']}" if arguments['container'].present?}#{' --previous' if arguments['previous'] == true}"
        answer([ text, *notes ].join("\n"), command)
      end

      def pod_metrics(environment_row:, arguments:)
        workload = find_workload(environment_row, arguments)
        pods = pods_of(environment_row, workload)
        command = "kubectl top pods #{pod_target(environment_row, workload)} -n #{workload[:namespace]}"
        return answer("#{label(workload)} has no pods.", command) if pods.empty?

        usage = begin
          api(environment_row).list("#{METRICS_API}/namespaces/#{segment(workload[:namespace])}/pods", "labelSelector" => selector_of(environment_row, workload)).items
        rescue KubernetesApi::NotFound
          fail! "The cluster has no metrics API (metrics.k8s.io), which metrics-server provides, so there is no CPU or memory to read."
        end
        by_pod = usage.index_by { |metric| metric.dig("metadata", "name") }
        read_at = usage.filter_map { |metric| metric["timestamp"] }.max
        rows = pods.map { |pod| usage_line(pod, by_pod[pod.dig("metadata", "name")]) }
        head = "Current CPU and memory of #{label(workload)}#{", read at #{read_at}" if read_at}. The metrics API keeps only " \
               "the latest reading, so this is now, not a history over a range."
        answer([ head, *rows ].join("\n"), command)
      end

      def describe_workload(environment_row:, arguments:)
        workload = find_workload(environment_row, arguments)
        object = workload[:object]
        lines = [ "#{label(workload)}, created #{object.dig('metadata', 'creationTimestamp')}" ]
        lines.concat(workload[:kind].key == CRONJOB ? cronjob_lines(environment_row, workload) : state_lines(workload))
        lines.concat(condition_lines(object.dig("status", "conditions")))
        lines.concat(container_spec_lines(template_of(workload)))
        pods = pods_of(environment_row, workload)
        lines.concat(pod_lines(pods))
        lines.concat(event_lines(environment_row, workload, pods))
        answer(lines.compact.join("\n"), "kubectl describe #{workload[:kind].key}/#{workload[:name]} -n #{workload[:namespace]}")
      end

      def rollout_history(environment_row:, arguments:)
        workload = find_workload(environment_row, arguments)
        rolling!(workload, "has no rollout history")
        revisions = revisions_of(environment_row, workload).first(Capabilities::Answers.limit(arguments, HISTORY_LIMIT))
        command = "kubectl rollout history #{workload[:kind].key}/#{workload[:name]} -n #{workload[:namespace]}"
        return answer("#{label(workload)} has no recorded revisions.", command) if revisions.empty?

        rows = revisions.map do |revision|
          [ "revision #{revision[:number]}", revision[:created], (revision[:current] ? "current" : nil), "images #{revision[:images].join(', ').presence || 'unknown'}",
            ("change cause #{revision[:cause]}" if revision[:cause].present?) ].compact.join(", ")
        end
        answer("Revisions of #{label(workload)}, newest first.\n#{rows.join("\n")}", command)
      end

      def list_events(environment_row:, arguments:)
        namespace = namespace_for(environment_row, arguments["namespace"])
        type = arguments["type"].presence_in(EVENT_TYPES) || EVENT_WARNING
        prefix = arguments["resource"].to_s.strip.split("/").last.to_s
        events = events_in(environment_row, namespace).select do |event|
          (type == EVENTS_ALL || event["type"] == type) && event.dig("involvedObject", "name").to_s.start_with?(prefix)
        end
        shown = events.first(Capabilities::Answers.limit(arguments, EVENT_LIMIT))
        command = "kubectl get events -n #{namespace} --sort-by=.lastTimestamp#{" --field-selector type=#{type}" unless type == EVENTS_ALL}"
        return answer("No #{type == EVENTS_ALL ? '' : "#{type} "}events in #{namespace}#{" about #{prefix}" if prefix.present?}.", command) if shown.empty?

        answer("#{shown.size} events in #{namespace}, newest first.\n#{shown.map { |event| event_line(event) }.join("\n")}", command)
      end

      def rollout_undo(environment_row:, arguments:)
        workload = find_workload(environment_row, arguments)
        rolling!(workload, "cannot be rolled back")
        number = Integer(arguments["revision"], exception: false)
        fail! "revision must be a revision number from the workload's rollout history." unless number&.positive?

        revision = revisions_of(environment_row, workload).find { |each| each[:number] == number }
        fail! "#{label(workload)} has no revision #{number}. Its rollout history shows the ones it keeps." unless revision
        return answer("#{label(workload)} already runs revision #{number}, so nothing changed.", status_command(workload)) if revision[:current]

        if workload[:kind].key == DEPLOYMENT
          fail! "#{label(workload)} is paused. Resume it before rolling it back." if workload[:object].dig("spec", "paused")

          change!(environment_row, workload, deployment_undo(workload[:object], revision[:source]), KubernetesApi::PATCH_JSON)
        else
          change!(environment_row, workload, revision[:source]["data"], KubernetesApi::PATCH_STRATEGIC)
        end
        answer("#{label(workload)} is going back to revision #{number} (images #{revision[:images].join(', ')}). Its pods roll out " \
               "again as its strategy says. Read its status again in a minute to see them come up.", status_command(workload))
      end

      def rollout_restart(environment_row:, arguments:)
        workload = find_workload(environment_row, arguments)
        rolling!(workload, "cannot be restarted this way")
        fail! "#{label(workload)} is paused. Resume it before restarting it." if workload[:object].dig("spec", "paused")

        at = Time.current.utc.iso8601
        body = { "spec" => { "template" => { "metadata" => { "annotations" => { RESTARTED_AT => at } } } } }
        change!(environment_row, workload, body, KubernetesApi::PATCH_STRATEGIC)
        answer("#{label(workload)} is restarting as of #{at}. Its pods are replaced as its strategy says. Read its status again in a minute to see them come up.",
               status_command(workload))
      end

      def scale_workload(environment_row:, arguments:)
        workload = find_workload(environment_row, arguments)
        fail! "#{label(workload)} cannot be scaled. Only deployments and statefulsets can." unless SCALABLE.include?(workload[:kind].key)
        replicas = Integer(arguments["replicas"], exception: false)
        fail! "replicas must be a whole number, 0 or more." unless replicas && replicas >= 0

        was = workload[:object].dig("spec", "replicas") || 1
        change!(environment_row, workload, { "spec" => { "replicas" => replicas } }, KubernetesApi::PATCH_MERGE, subresource: "scale")
        autoscaler = autoscaler_of(environment_row, workload)
        note = autoscaler ? " The autoscaler #{autoscaler} also sets its replicas, and will move them back within its own bounds." : ""
        answer("#{label(workload)} now asks for #{replicas} pods, it asked for #{was}.#{note}", status_command(workload))
      end

      # Puts each connected namespace's workloads, services and ingresses on the map, with what serves what. A list the
      # token may not read is a gap, and the sweep takes nothing of that kind as gone. Any other failure, such as an
      # expired token, fails the sweep and leaves the map as it was.
      def map_of(environment_row)
        api = api(environment_row)
        mapping = MapReading.new(api.host)
        gaps = []
        connected(environment_row).each do |namespace|
          [ *WORKLOADS.values, SERVICE, INGRESS ].each do |kind|
            listing = api.list(self.class.collection(kind, namespace))
            if listing.incomplete?
              gaps << ResourceMap::Gap.new(text: "Only the first #{KubernetesApi::PAGE_SIZE * KubernetesApi::MAX_PAGES} #{kind.plural} in #{namespace} were read.",
                                           kinds: kinds_listed_by(kind))
            end
            listing.items.reject { |item| kind.key == JOB && owned_by?(item, CRONJOB) }.each { |item| mapping.add(kind, item) }
          rescue KubernetesApi::Forbidden, KubernetesApi::NotFound => error
            gaps << ResourceMap::Gap.new(text: Sentence.join("#{kind.plural.capitalize} in #{namespace} could not be read", error), kinds: kinds_listed_by(kind))
          end
        end
        mapping.connect!
        ResourceMap::Snapshot.new(resources: mapping.resources, links: mapping.links, gaps: gaps)
      end

      # Builds the snapshot for map_of. A service is served by the workloads its selector picks, an ingress by the
      # services it routes to, and a hostname by the ingress or load balancer that answers for it.
      class MapReading
        attr_reader :resources, :links

        def initialize(host)
          @host = host
          @resources = []
          @links = []
          @workloads = []
          @services = []
          @ingresses = []
        end

        def add(kind, item)
          namespace = item.dig("metadata", "namespace")
          found = ResourceMap::Found.new(provider: PROVIDER_KEY, account: "#{@host}/#{namespace}", kind: kind.map_kind,
                                         external_id: "#{namespace}/#{kind.key}/#{item.dig('metadata', 'name')}",
                                         name: item.dig("metadata", "name"), status: Kubernetes.state_of(kind.key, item),
                                         details: details(kind, item))
          @resources << found
          case kind.key
          when SERVICE.key then @services << [ found, item ]
          when INGRESS.key then @ingresses << [ found, item ]
          else @workloads << [ found, item, Kubernetes.template_labels(kind.key, item) ]
          end
        end

        def connect!
          @services.each { |found, service| serve_service(found, service) }
          @ingresses.each { |found, ingress| serve_ingress(found, ingress) }
        end

        private

        def details(kind, item)
          {
            "type" => kind.key == SERVICE.key ? "Service (#{item.dig('spec', 'type') || 'ClusterIP'})" : kind.name,
            "namespace" => item.dig("metadata", "namespace"),
            "instances" => Kubernetes.desired(kind.key, item),
            "schedule" => item.dig("spec", "schedule"),
            "images" => Kubernetes.images(kind.key, item).join(", ").presence,
            ResourceMap::TAGS => item.dig("metadata", "labels").presence
          }.compact
        end

        def serve_service(found, service)
          selector = service.dig("spec", "selector").to_h
          if selector.any?
            namespace = service.dig("metadata", "namespace")
            @workloads.each do |workload, item, labels|
              next unless item.dig("metadata", "namespace") == namespace && selector <= labels

              link(found.key, workload.key)
            end
          end
          Array(service.dig("status", "loadBalancer", "ingress")).filter_map { |entry| entry["hostname"].presence }.each { |host| domain(host, found) }
        end

        def serve_ingress(found, ingress)
          namespace = ingress.dig("metadata", "namespace")
          backends = [ ingress.dig("spec", "defaultBackend", "service", "name"),
                       *Array(ingress.dig("spec", "rules")).flat_map { |rule| Array(rule.dig("http", "paths")).map { |path| path.dig("backend", "service", "name") } } ]
          backends.compact.uniq.each do |name|
            service = @services.find { |each, item| item.dig("metadata", "namespace") == namespace && each.name == name }
            link(found.key, service.first.key) if service
          end
          Array(ingress.dig("spec", "rules")).filter_map { |rule| rule["host"].presence }.reject { |host| host.include?("*") }.uniq.each { |host| domain(host, found) }
        end

        def domain(host, server)
          found = ResourceMap.domain(host)
          @resources << found
          link(found.key, server.key)
        end

        def link(from, to)
          @links << ResourceMap::FoundLink.new(from: from, to: to, relation: ResourceMap::RELATION_SERVED_BY)
        end
      end

      # How a workload stands, in a word the map shows. A rollout that finished with too few pods ready is degraded, such
      # as pods that crash after the rollout completed, never progressing, which would read as busy.
      def self.state_of(kind, item)
        spec = item["spec"].to_h
        status = item["status"].to_h
        case kind
        when DEPLOYMENT
          desired = spec.fetch("replicas", 1)
          return "scaled down" if desired.zero?
          return "failed" if Array(status["conditions"]).any? { |condition| condition["reason"] == "ProgressDeadlineExceeded" }

          updated = status["updatedReplicas"].to_i >= desired
          rolled_out(status["readyReplicas"].to_i >= desired, updated, finished: updated && rollout_complete?(status))
        when STATEFULSET
          desired = spec.fetch("replicas", 1)
          return "scaled down" if desired.zero?

          updated = status["currentRevision"] == status["updateRevision"]
          rolled_out(status["readyReplicas"].to_i >= desired, updated, finished: updated)
        when DAEMONSET
          desired = status["desiredNumberScheduled"].to_i
          updated = status["updatedNumberScheduled"].to_i >= desired
          rolled_out(status["numberReady"].to_i >= desired, updated, finished: updated)
        when CRONJOB then spec["suspend"] ? "suspended" : "scheduled"
        # A LoadBalancer service waits for its cloud to hand it an address, and every other service routes once it exists.
        when SERVICE.key then spec["type"] == "LoadBalancer" && Array(status.dig("loadBalancer", "ingress")).empty? ? "pending" : "active"
        when INGRESS.key then "active"
        when JOB
          return "succeeded" if condition?(status, "Complete")
          return "failed" if condition?(status, "Failed")

          "running"
        end
      end

      def self.rolled_out(ready, updated, finished:)
        return "running" if ready && updated

        finished ? "degraded" : "progressing"
      end

      # Kubernetes marks a Deployment's rollout complete with its Progressing condition's NewReplicaSetAvailable reason,
      # which stays when pods fail afterwards (kubernetes.io, Deployments, Complete Deployment).
      def self.rollout_complete?(status) = Array(status["conditions"]).any? { |condition| condition["type"] == "Progressing" && condition["reason"] == "NewReplicaSetAvailable" }

      def self.condition?(status, type) = Array(status["conditions"]).any? { |condition| condition["type"] == type && condition["status"] == "True" }

      def self.desired(kind, item)
        case kind
        when DEPLOYMENT, STATEFULSET then item.dig("spec", "replicas") || 1
        when DAEMONSET then item.dig("status", "desiredNumberScheduled")
        end
      end

      def self.pod_template(kind, item)
        kind == CRONJOB ? item.dig("spec", "jobTemplate", "spec", "template") : item.dig("spec", "template")
      end

      def self.template_labels(kind, item) = pod_template(kind, item).to_h.dig("metadata", "labels").to_h

      def self.images(kind, item) = Array(pod_template(kind, item).to_h.dig("spec", "containers")).filter_map { |container| container["image"] }

      private

      # What a list of one kind puts on the map. Services and ingresses also put the hostnames they answer on there.
      def kinds_listed_by(kind) = [ kind.map_kind, (ResourceMap::KIND_DOMAIN if [ SERVICE, INGRESS ].include?(kind)) ].compact

      def api(environment_row)
        settings = ConnectionSettings.of(environment_row)
        server, token, ca = settings.field(SERVER), settings.credential(TOKEN), settings.credential(CA)
        fail! "This environment has no Kubernetes credentials. Reconnect it on the Integrations page." if [ server, token, ca ].any?(&:blank?)

        @api ||= KubernetesApi.new(server: server, token: token, ca: ca)
      rescue KubernetesApi::Error => error
        fail! error.message
      end

      def connected(environment_row)
        namespaces = self.class.namespace_list(ConnectionSettings.of(environment_row).field(NAMESPACES))
        namespaces.presence || fail!("This environment has no namespaces. Reconnect it on the Integrations page.")
      end

      # The namespace asked for, which must be one the connection reaches. Without one, the connection's only namespace.
      def namespace_for(environment_row, asked)
        namespaces = connected(environment_row)
        asked = asked.to_s.strip
        if asked.empty?
          return namespaces.first if namespaces.one? && namespaces.first != ALL_NAMESPACES

          fail! "Say which namespace. This connection reaches #{namespaces == [ ALL_NAMESPACES ] ? 'every namespace' : namespaces.join(', ')}."
        end
        fail! "#{asked} is not a namespace name." unless asked.match?(NAMESPACE_FORMAT)
        return asked if namespaces.include?(ALL_NAMESPACES) || namespaces.include?(asked)

        fail! "This connection reaches only #{namespaces.join(', ')}, not #{asked}."
      end

      def segment(value) = self.class.segment(value)

      def listed(environment_row, kind, namespace)
        listing = api(environment_row).list(self.class.collection(kind, namespace))
        note = "Only the first #{listing.items.size} #{kind.plural} in #{namespace} are shown." if listing.incomplete?
        [ listing.items, note ]
      rescue KubernetesApi::Forbidden, KubernetesApi::NotFound => error
        [ [], Sentence.join("#{kind.plural.capitalize} in #{namespace} could not be listed", error) ]
      end

      def workload_line(kind, item)
        name = "#{kind.key}/#{item.dig('metadata', 'name')} in #{item.dig('metadata', 'namespace')}"
        state = self.class.state_of(kind.key, item)
        case kind.key
        when DEPLOYMENT, STATEFULSET then "#{name}: #{item.dig('status', 'readyReplicas').to_i} of #{self.class.desired(kind.key, item)} ready, #{state}"
        when DAEMONSET then "#{name}: #{item.dig('status', 'numberReady').to_i} of #{self.class.desired(kind.key, item).to_i} ready, #{state}"
        when CRONJOB then "#{name}: schedule #{item.dig('spec', 'schedule')}, #{state}, last run #{item.dig('status', 'lastScheduleTime') || 'never'}"
        else "#{name}: #{state}, #{item.dig('status', 'succeeded').to_i} succeeded, #{item.dig('status', 'failed').to_i} failed"
        end
      end

      def network_line(kind, item)
        name = "#{kind.key}/#{item.dig('metadata', 'name')} in #{item.dig('metadata', 'namespace')}"
        if kind == SERVICE
          ports = Array(item.dig("spec", "ports")).map { |port| [ port["port"], port["targetPort"] ].compact.join(" to ") }
          "#{name}: #{item.dig('spec', 'type') || 'ClusterIP'}, ports #{ports.join(', ').presence || 'none'}, selects #{item.dig('spec', 'selector').to_h.map { |key, value| "#{key}=#{value}" }.join(',').presence || 'nothing'}"
        else
          hosts = Array(item.dig("spec", "rules")).filter_map { |rule| rule["host"] }
          "#{name}: hosts #{hosts.join(', ').presence || 'any'}"
        end
      end

      # The workload asked for, read live. resource is kind/name, the map's namespace/kind/name, or a name alone that
      # only one kind of workload in the namespace has.
      def find_workload(environment_row, arguments)
        asked = arguments["resource"].to_s.strip
        fail! "Say which workload, as kind/name such as deployment/web. list_resources shows them." if asked.empty?

        parts = asked.split("/")
        fail! "#{asked} is not a workload. Name it as kind/name, such as deployment/web." if parts.size > 3 || parts.any?(&:empty?)

        namespace_given, kind_given, name = parts.size == 3 ? parts : [ arguments["namespace"], *(parts.size == 2 ? parts : [ nil, parts.first ]) ]
        namespace = namespace_for(environment_row, namespace_given)
        kinds = kind_given ? [ kind_named(kind_given) ] : WORKLOADS.values
        found = kinds.filter_map do |kind|
          object = api(environment_row).get("#{self.class.collection(kind, namespace)}/#{segment(name)}")
          { kind: kind, namespace: namespace, name: name, object: object }
        rescue KubernetesApi::NotFound
          nil
        rescue KubernetesApi::Forbidden => error
          fail! Sentence.all(error, "The service account's role cannot read #{kind.plural} in #{namespace}.")
        end
        # A name alone can match a workload of each kind, and its id is kind/name.
        Named.find(found, name, id: ->(each) { "#{each[:kind].key}/#{each[:name]}" }, name: :name, provider: PROVIDER, connection: environment_row) ||
          fail!("No #{kind_given ? kinds.first.key : 'workload'} called #{name} in #{namespace}. list_resources shows what there is.")
      end

      def kind_named(given)
        key = given.to_s.downcase
        WORKLOADS.values.find { |kind| kind.key == key || kind.aliases.include?(key) } ||
          fail!("#{given} is not a workload kind. Use deployment, statefulset, daemonset, cronjob or job.")
      end

      def label(workload) = "#{workload[:kind].key}/#{workload[:name]} in #{workload[:namespace]}"

      def object_path(workload) = "#{self.class.collection(workload[:kind], workload[:namespace])}/#{segment(workload[:name])}"

      def rolling!(workload, refusal)
        fail! "#{label(workload)} #{refusal}. Only deployments, statefulsets and daemonsets roll out." unless ROLLING.include?(workload[:kind].key)
      end

      def template_of(workload) = self.class.pod_template(workload[:kind].key, workload[:object]).to_h

      # A label selector as the API reads it, from a workload's matchLabels and matchExpressions.
      def selector(spec_selector)
        labels = spec_selector.to_h.fetch("matchLabels", {}).map { |key, value| "#{key}=#{value}" }
        expressions = Array(spec_selector.to_h["matchExpressions"]).filter_map do |expression|
          key = expression["key"]
          values = Array(expression["values"]).join(",")
          case expression["operator"]
          when "In" then "#{key} in (#{values})"
          when "NotIn" then "#{key} notin (#{values})"
          when "Exists" then key
          when "DoesNotExist" then "!#{key}"
          end
        end
        (labels + expressions).join(",")
      end

      # The selector a workload's pods carry. A cronjob's pods belong to its jobs, so it is its newest job's.
      def selector_of(environment_row, workload)
        return selector(workload[:object].dig("spec", "selector")) unless workload[:kind].key == CRONJOB

        job = jobs_of(environment_row, workload).first
        job ? selector(job.dig("spec", "selector")) : ""
      end

      def pods_of(environment_row, workload)
        found = selector_of(environment_row, workload)
        return [] if found.empty?

        api(environment_row).list("#{CORE}/namespaces/#{segment(workload[:namespace])}/pods", "labelSelector" => found).items
                            .sort_by { |pod| pod.dig("metadata", "creationTimestamp").to_s }.reverse
      end

      def jobs_of(environment_row, workload)
        uid = workload[:object].dig("metadata", "uid")
        api(environment_row).list(self.class.collection(WORKLOADS.fetch(JOB), workload[:namespace])).items
                            .select { |job| controlled_by?(job, uid) }
                            .sort_by { |job| job.dig("metadata", "creationTimestamp").to_s }.reverse
      end

      def controlled_by?(item, uid) = Array(item.dig("metadata", "ownerReferences")).any? { |owner| owner["controller"] && owner["uid"] == uid }

      def owned_by?(item, kind) = Array(item.dig("metadata", "ownerReferences")).any? { |owner| owner["kind"].to_s.casecmp?(WORKLOADS.fetch(kind).name) }

      def log_pods(environment_row, arguments)
        if arguments["pod"].present?
          namespace = namespace_for(environment_row, arguments["namespace"])
          pod = begin
            api(environment_row).get("#{CORE}/namespaces/#{segment(namespace)}/pods/#{segment(arguments['pod'])}")
          rescue KubernetesApi::NotFound
            fail! "No pod called #{arguments['pod']} in #{namespace}. Kubernetes keeps no logs of a pod that is gone."
          end
          return [ namespace, [ pod ], "pod #{arguments['pod']} in #{namespace}", arguments["pod"] ]
        end
        fail! "Say which workload, or a pod by name." if arguments["resource"].blank?

        workload = find_workload(environment_row, arguments)
        [ workload[:namespace], pods_of(environment_row, workload), label(workload), pod_target(environment_row, workload) ]
      end

      def container_lines(environment_row, namespace, pod, container, started, ended, previous, matcher)
        query = { "container" => container, "timestamps" => true, "sinceTime" => started.utc.iso8601, "tailLines" => LOG_FETCH,
                  "limitBytes" => LOG_BYTES, "previous" => (true if previous) }
        text = api(environment_row).text("#{CORE}/namespaces/#{segment(namespace)}/pods/#{segment(pod)}/log", query)
        text.each_line.filter_map do |raw|
          stamp, line = raw.chomp.split(" ", 2)
          at = Telemetry.parse_time(stamp)
          next unless at && at <= ended && matcher.call(line.to_s)

          Telemetry::LogLine.new(at: at, source: "#{pod}/#{container}", text: line.to_s)
        end
      end

      def line_matcher(arguments)
        text, exclude = arguments["text"].to_s.downcase.presence, arguments["exclude"].to_s.downcase.presence
        pattern = Regexp.new(arguments["regex"], timeout: REGEX_TIMEOUT) if arguments["regex"].present?
        lambda do |line|
          lowered = line.downcase
          (text.nil? || lowered.include?(text)) && (exclude.nil? || !lowered.include?(exclude)) && (pattern.nil? || pattern.match?(line))
        end
      rescue RegexpError => error
        fail! Sentence.join("regex could not be read", error)
      end

      def answer(text, command) = Telemetry.result("#{text}\n#{format(CHECK_LINE, command: command)}", link: nil)

      # How kubectl names a workload's pods, by their label selector, or the workload itself when it has none yet.
      def pod_target(environment_row, workload)
        found = selector_of(environment_row, workload)
        found.empty? ? "#{workload[:kind].key}/#{workload[:name]}" : "-l '#{found}'"
      end

      def status_command(workload) = "kubectl rollout status #{workload[:kind].key}/#{workload[:name]} -n #{workload[:namespace]}"

      def quantity(value)
        match = value.to_s.strip.match(QUANTITY)
        match && match[1].to_f * SUFFIXES.fetch(match[2].to_s)
      end

      def usage_line(pod, metric)
        name = pod.dig("metadata", "name")
        return "#{name}: no reading yet (#{pod.dig('status', 'phase')})" unless metric

        containers = Array(pod.dig("spec", "containers"))
        cpu = Array(metric["containers"]).sum { |container| quantity(container.dig("usage", "cpu")).to_f }
        memory = Array(metric["containers"]).sum { |container| quantity(container.dig("usage", "memory")).to_f }
        "#{name}: CPU #{cores(cpu)}#{bounds(containers, 'cpu') { |value| cores(value) }}, " \
          "memory #{mebibytes(memory)}#{bounds(containers, 'memory') { |value| mebibytes(value) }}"
      end

      # A pod's requests and limits for one resource, added up over its containers, when every container sets them.
      def bounds(containers, resource)
        parts = %w[requests limits].filter_map do |which|
          values = containers.map { |container| quantity(container.dig("resources", which, resource)) }
          "#{which.delete_suffix('s')} #{yield values.sum}" if values.any? && values.all?
        end
        parts.any? ? " (#{parts.join(', ')})" : ""
      end

      def cores(value) = "#{value.round(3)} cores"

      def mebibytes(value) = "#{(value / MIB).round(1)} MiB"

      def state_lines(workload)
        spec = workload[:object]["spec"].to_h
        status = workload[:object]["status"].to_h
        case workload[:kind].key
        when DEPLOYMENT
          [ "Replicas: #{spec.fetch('replicas', 1)} desired, #{status['readyReplicas'].to_i} ready, #{status['updatedReplicas'].to_i} up to date, " \
            "#{status['availableReplicas'].to_i} available, #{status['unavailableReplicas'].to_i} unavailable",
            "Strategy: #{spec.dig('strategy', 'type') || 'RollingUpdate'}#{', paused' if spec['paused']}, revision #{workload[:object].dig('metadata', 'annotations', REVISION)}" ]
        when STATEFULSET
          [ "Replicas: #{spec.fetch('replicas', 1)} desired, #{status['readyReplicas'].to_i} ready, #{status['updatedReplicas'].to_i} up to date",
            "Revision: current #{status['currentRevision']}, update #{status['updateRevision']}, strategy #{spec.dig('updateStrategy', 'type') || 'RollingUpdate'}" ]
        when DAEMONSET
          [ "Pods: #{status['desiredNumberScheduled'].to_i} wanted, #{status['numberReady'].to_i} ready, #{status['updatedNumberScheduled'].to_i} up to date, " \
            "#{status['numberAvailable'].to_i} available, #{status['numberMisscheduled'].to_i} on nodes they should not be on" ]
        when JOB
          [ "Pods: #{status['active'].to_i} active, #{status['succeeded'].to_i} succeeded, #{status['failed'].to_i} failed, " \
            "#{spec['completions'] || 1} completions wanted, backoff limit #{spec['backoffLimit'] || 6}",
            ("Started #{status['startTime']}#{", finished #{status['completionTime']}" if status['completionTime']}" if status["startTime"]) ]
        end
      end

      def cronjob_lines(environment_row, workload)
        spec = workload[:object]["spec"].to_h
        status = workload[:object]["status"].to_h
        jobs = jobs_of(environment_row, workload).first(JOBS_SHOWN).map do |job|
          outcome = self.class.state_of(JOB, job)
          reason = Array(job.dig("status", "conditions")).find { |condition| condition["type"] == "Failed" }&.dig("reason")
          "  #{job.dig('metadata', 'name')}: #{outcome}#{" (#{reason})" if reason}, started #{job.dig('status', 'startTime') || 'not yet'}"
        end
        [ "Schedule: #{spec['schedule']}#{" #{spec['timeZone']}" if spec['timeZone']}#{', suspended' if spec['suspend']}, concurrency #{spec['concurrencyPolicy'] || 'Allow'}",
          "Last scheduled #{status['lastScheduleTime'] || 'never'}, last succeeded #{status['lastSuccessfulTime'] || 'never'}, #{Array(status['active']).size} running now",
          (jobs.any? ? "Recent jobs, newest first:\n#{jobs.join("\n")}" : "Recent jobs: none kept") ]
      end

      def condition_lines(conditions)
        return [] if conditions.blank?

        rows = conditions.map do |condition|
          "  #{condition['type']} #{condition['status']}#{", #{condition['reason']}" if condition['reason']}" \
            "#{": #{condition['message']}" if condition['message']}#{", since #{condition['lastTransitionTime']}" if condition['lastTransitionTime']}"
        end
        [ "Conditions:\n#{rows.join("\n")}" ]
      end

      # What each container runs and is given. Environment values are left out, since they can hold secrets.
      def container_spec_lines(template)
        containers = Array(template.dig("spec", "containers"))
        return [] if containers.empty?

        rows = containers.map do |container|
          resources = container["resources"].to_h
          sizes = %w[requests limits].filter_map do |which|
            set = resources[which].to_h.slice("cpu", "memory")
            "#{which} #{set.map { |key, value| "#{key} #{value}" }.join(' ')}" if set.any?
          end
          probes = %w[startupProbe livenessProbe readinessProbe].filter_map { |probe| probe_text(probe, container[probe]) }
          "  #{container['name']}: #{container['image']}, #{sizes.join(', ').presence || 'no requests or limits'}, " \
            "#{probes.join(', ').presence || 'no probes'}"
        end
        [ "Containers:\n#{rows.join("\n")}" ]
      end

      def probe_text(name, probe)
        return nil unless probe

        target = if probe["httpGet"] then "HTTP #{probe.dig('httpGet', 'path')} port #{probe.dig('httpGet', 'port')}"
        elsif probe["tcpSocket"] then "TCP port #{probe.dig('tcpSocket', 'port')}"
        elsif probe["grpc"] then "gRPC port #{probe.dig('grpc', 'port')}"
        elsif probe["exec"] then "a command"
        end
        "#{name.delete_suffix('Probe')} probe #{target}, after #{probe['initialDelaySeconds'] || 0}s, every #{probe['periodSeconds'] || 10}s, " \
          "fails after #{probe['failureThreshold'] || 3}"
      end

      def pod_lines(pods)
        return [ "Pods: none" ] if pods.empty?

        rows = pods.first(PODS_SHOWN).map do |pod|
          statuses = Array(pod.dig("status", "containerStatuses"))
          ready = statuses.count { |status| status["ready"] }
          restarts = statuses.sum { |status| status["restartCount"].to_i }
          states = statuses.filter_map { |status| container_state(status) }
          "  #{pod.dig('metadata', 'name')}: #{pod.dig('status', 'phase')}, #{ready} of #{statuses.size} ready, #{restarts} restarts, " \
            "node #{pod.dig('spec', 'nodeName') || 'none yet'}, started #{pod.dig('status', 'startTime') || 'not yet'}#{"\n    #{states.join("\n    ")}" if states.any?}"
        end
        more = pods.size > PODS_SHOWN ? "\n  #{pods.size - PODS_SHOWN} more pods not shown" : ""
        [ "Pods, newest first:\n#{rows.join("\n")}#{more}" ]
      end

      def container_state(status)
        waiting = status.dig("state", "waiting")
        last = status.dig("lastState", "terminated")
        parts = []
        parts << "waiting: #{waiting['reason']}#{" (#{waiting['message'].to_s.truncate(200)})" if waiting['message'].present?}" if waiting
        parts << "last stopped: #{last['reason']}, exit code #{last['exitCode']}, at #{last['finishedAt']}" if last
        "#{status['name']} #{parts.join(', ')}" if parts.any?
      end

      # The latest events about the workload, its pods, and the replica sets or jobs between them.
      def event_lines(environment_row, workload, pods)
        names = [ workload[:name], *pods.map { |pod| pod.dig("metadata", "name") } ]
        events = events_in(environment_row, workload[:namespace]).select do |event|
          name = event.dig("involvedObject", "name").to_s
          names.include?(name) || name.start_with?("#{workload[:name]}-")
        end
        return [ "Events: none kept (the API server keeps them for an hour by default)" ] if events.empty?

        [ "Latest events, newest first:\n#{events.first(EVENTS_SHOWN).map { |event| "  #{event_line(event)}" }.join("\n")}" ]
      rescue KubernetesApi::Forbidden => error
        [ Sentence.join("Events could not be read", error) ]
      end

      def events_in(environment_row, namespace)
        api(environment_row).list("#{CORE}/namespaces/#{segment(namespace)}/events").items.sort_by { |event| event_time(event).to_s }.reverse
      end

      def event_time(event)
        event["lastTimestamp"] || event.dig("series", "lastObservedTime") || event["eventTime"] || event.dig("metadata", "creationTimestamp")
      end

      def event_line(event)
        count = event["count"] || event.dig("series", "count")
        object = "#{event.dig('involvedObject', 'kind').to_s.downcase}/#{event.dig('involvedObject', 'name')}"
        "#{event_time(event)} #{event['type']} #{event['reason']} #{object}: #{Chat::SecretFree.redacted(event['message'].to_s.squish).truncate(300)}#{" (#{count} times)" if count.to_i > 1}"
      end

      # A workload's revisions, newest first. A deployment keeps them as replica sets, a statefulset or daemonset as
      # controller revisions, each owned by the workload, as kubectl rollout history reads them.
      def revisions_of(environment_row, workload)
        object = workload[:object]
        uid = object.dig("metadata", "uid")
        query = { "labelSelector" => selector(object.dig("spec", "selector")) }
        namespace = segment(workload[:namespace])
        revisions = if workload[:kind].key == DEPLOYMENT
          current = object.dig("metadata", "annotations", REVISION).to_i
          api(environment_row).list("#{APPS}/namespaces/#{namespace}/replicasets", query).items.select { |set| controlled_by?(set, uid) }.filter_map do |set|
            number = set.dig("metadata", "annotations", REVISION).to_i
            next unless number.positive?

            { number: number, created: set.dig("metadata", "creationTimestamp"), current: number == current, source: set,
              cause: set.dig("metadata", "annotations", CHANGE_CAUSE), images: self.class.images(DEPLOYMENT, set) }
          end
        else
          # Going back to a revision gives it the next number, so the newest is always what the workload asks for now.
          listed = api(environment_row).list("#{APPS}/namespaces/#{namespace}/controllerrevisions", query).items.select { |revision| controlled_by?(revision, uid) }
          newest = listed.map { |revision| revision["revision"].to_i }.max
          listed.map do |revision|
            { number: revision["revision"].to_i, created: revision.dig("metadata", "creationTimestamp"), source: revision,
              current: revision["revision"].to_i == newest, cause: revision.dig("metadata", "annotations", CHANGE_CAUSE),
              images: Array(revision.dig("data", "spec", "template", "spec", "containers")).filter_map { |container| container["image"] } }
          end
        end
        revisions.sort_by { |revision| -revision[:number] }
      end

      # Going back as kubectl rollout undo does for a deployment, in one JSON patch. The pod template is the replica set's
      # without its pod-template-hash label, and the annotations are the replica set's over the ones the deployment keeps.
      def deployment_undo(deployment, replica_set)
        template = replica_set.dig("spec", "template").deep_dup
        template["metadata"] = template["metadata"].to_h
        template["metadata"]["labels"] = template["metadata"]["labels"].to_h.except(POD_TEMPLATE_HASH)
        kept = deployment.dig("metadata", "annotations").to_h.slice(*ANNOTATIONS_KEPT)
        annotations = kept.merge(replica_set.dig("metadata", "annotations").to_h.except(*ANNOTATIONS_KEPT))
        [ { "op" => "replace", "path" => "/spec/template", "value" => template },
          { "op" => "replace", "path" => "/metadata/annotations", "value" => annotations } ]
      end

      def autoscaler_of(environment_row, workload)
        found = api(environment_row).list("#{AUTOSCALING}/namespaces/#{segment(workload[:namespace])}/horizontalpodautoscalers").items.find do |autoscaler|
          target = autoscaler.dig("spec", "scaleTargetRef").to_h
          target["kind"] == workload[:kind].name && target["name"] == workload[:name]
        end
        found&.dig("metadata", "name")
      rescue KubernetesApi::Error
        nil
      end

      # A refusal names what the service account's role needs, so a person can give it and run the change again.
      def change!(environment_row, workload, body, type, subresource: nil)
        api(environment_row).patch([ object_path(workload), subresource ].compact.join("/"), body, type)
      rescue KubernetesApi::Forbidden => error
        permission = [ workload[:kind].plural, subresource ].compact.join("/")
        fail! Sentence.all(error, "The service account's role cannot make this change. Give it patch on #{permission} in #{workload[:namespace]}, then run it again.")
      end
    end
  end
end
