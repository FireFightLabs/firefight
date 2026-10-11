module Integrations
  module MapEventSources
    # A cluster's changes, followed with a watch on each list the map reads (Packs::Kubernetes.map_lists), every two
    # minutes. Each watch starts from the resourceVersion the last one reached and ends after about 50 seconds, the API
    # server closing it after sending a bookmark, so a quiet list stays current. The watches run side by side. A list
    # whose version the server no longer keeps answers 410 Gone, and the connection is read in full. The token's role
    # needs watch beside get and list. (Kubernetes API concepts,
    # https://kubernetes.io/docs/reference/using-api/api-concepts/#efficient-detection-of-changes)
    #
    # A Job its CronJob made is not on the map, so its change is the CronJob's, whose runs it is. Each namespace's Warning
    # events are watched too (core/v1 Event, fieldSelector type=Warning), each about the workload on the map it names or
    # whose pod, replica set or job it names, followed up through ownerReferences. A warning changes nothing the map
    # shows, but it wakes the watches reading the workload. A token that may not watch events still follows the rest.
    class Kubernetes < MapEventSource
      EVERY = 2.minutes
      # At most this many watches are open at once, so many namespaces never open a connection each.
      WATCHERS = 16
      ADDED = "ADDED".freeze
      MODIFIED = "MODIFIED".freeze
      DELETED = "DELETED".freeze
      ACTIONS = { ADDED => ResourceMap::Event::ADDED, MODIFIED => ResourceMap::Event::UPDATED, DELETED => ResourceMap::Event::REMOVED }.freeze
      WARNING_QUERY = { "fieldSelector" => "type=#{Packs::Kubernetes::EVENT_WARNING}" }.freeze
      # The most objects one watch reads to find the workload a warning is about, so a burst never reads the cluster at
      # length.
      OWNER_READS = 50
      WATCH_NEEDED = "The token's role may not watch %<lists>s, which following changes as they happen needs. Allow watch beside " \
                     "get and list on what Firefight reads".freeze

      # What one watch found: its events, the version it reached, and whether the server no longer kept where it began.
      Watched = Data.define(:events, :version, :gone, :forbidden, :error)

      class << self
        def verify(**) = false

        def events(_payload, headers:) = []

        def limits = "Firefight watches the cluster every 2 minutes, so a workload, service or ingress changing reaches the map within about 3 " \
                     "minutes. A ConfigMap a workload reads, and a workload's labels a service picks it by, change on the map at each hourly sweep."

        def poll_every = EVERY

        # The cursor holds each list's version by "<namespace>/<plural>". A list without one, the first time or a namespace
        # added since, starts from now. A list whose version is gone starts again from now, and the connection is read in
        # full once.
        def poll(row, since:)
          api = Packs::Kubernetes.client_for(row)
          versions = cursor_of(since)
          lists = Packs::Kubernetes.map_lists(row) + warning_lists(row)
          started, following = lists.partition { |kind, namespace| versions[list_key(kind, namespace)].blank? }
          started.each { |kind, namespace| versions[list_key(kind, namespace)] = current_version(api, kind, namespace) }

          watched = watch_all(api, following, versions)
          forbidden = watched.select { |(kind, _namespace), result| result.forbidden && kind != Packs::Kubernetes::WARNINGS }.map { |(kind, namespace), _result| "#{kind.plural} in #{namespace}" }
          raise MapEventSource::Refused, "#{format(WATCH_NEEDED, lists: forbidden.to_sentence)}." if forbidden.any?

          failed = watched.values.find(&:error)
          raise failed.error if failed

          events = watched.flat_map do |(kind, namespace), result|
            versions[list_key(kind, namespace)] = result.gone ? current_version(api, kind, namespace) : result.version
            # Events the server no longer keeps change nothing on the map, so only a mapped list is read again in full.
            result.gone && kind != Packs::Kubernetes::WARNINGS ? [ full_read(kind, namespace, versions[list_key(kind, namespace)]) ] : result.events
          end
          MapEventSource::Polled.new(events: events, cursor: versions.slice(*lists.map { |kind, namespace| list_key(kind, namespace) }).compact.to_json)
        end

        private

        def cursor_of(since)
          parsed = since.present? ? JSON.parse(since) : {}
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          {}
        end

        def list_key(kind, namespace) = "#{namespace}/#{kind.plural}"

        def warning_lists(row)
          Packs::Kubernetes.namespace_list(ConnectionSettings.of(row).field(Packs::Kubernetes::NAMESPACES)).map { |namespace| [ Packs::Kubernetes::WARNINGS, namespace ] }
        end

        # The list's own version now, from a list of one item, where a watch from it sees only what changes after.
        # A list the token may not read is not on the map either (Packs::Kubernetes#map_of), so it is not followed.
        def current_version(api, kind, namespace)
          api.get(Packs::Kubernetes.collection(kind, namespace), "limit" => 1).dig("metadata", "resourceVersion").to_s
        rescue KubernetesApi::Forbidden, KubernetesApi::NotFound
          nil
        end

        # Every list's watch side by side, each answering a Watched. Nothing here touches the database. The job's thread
        # lets the watchers load code while it waits for them.
        def watch_all(api, lists, versions)
          queue = Queue.new
          lists.each { |list| queue << list }
          queue.close
          found = {}
          lock = Mutex.new
          watchers = Array.new([ WATCHERS, lists.size ].min) do
            Thread.new do
              Rails.application.executor.wrap do
                while (list = queue.pop)
                  result = watch_one(api, *list, versions[list_key(*list)])
                  lock.synchronize { found[list] = result }
                end
              end
            end
          end
          ActiveSupport::Dependencies.interlock.permit_concurrent_loads { watchers.each(&:join) }
          found
        end

        def watch_one(api, kind, namespace, version)
          events = []
          reached = version
          warnings = kind == Packs::Kubernetes::WARNINGS
          owners = OwnerReads.new(api)
          query = warnings ? { query: WARNING_QUERY } : {}
          api.watch(Packs::Kubernetes.collection(kind, namespace), resource_version: version, **query) do |change|
            item = change["object"].to_h
            reached = item.dig("metadata", "resourceVersion").presence || reached
            event = warnings ? warning_of(api, owners, namespace, change["type"], item) : event_of(api, kind, namespace, change["type"], item)
            events << event if event
          end
          Watched.new(events: events, version: reached, gone: false, forbidden: false, error: nil)
        rescue KubernetesApi::Gone
          Watched.new(events: [], version: version, gone: true, forbidden: false, error: nil)
        rescue KubernetesApi::NotFound
          Watched.new(events: [], version: version, gone: false, forbidden: false, error: nil)
        rescue KubernetesApi::Forbidden
          Watched.new(events: [], version: version, gone: false, forbidden: true, error: nil)
        rescue Integrations::Error => error
          Watched.new(events: [], version: version, gone: false, forbidden: false, error: error)
        end

        # An object added, changed or deleted, about the one resource it is on the map, or a Job about the CronJob that made
        # it, which is then updated. A bookmark only moves the version.
        def event_of(api, kind, namespace, type, item)
          action = ACTIONS[type]
          name = item.dig("metadata", "name")
          return unless action && name.present?

          unless Packs::Kubernetes.on_map?(kind, item)
            name = Array(item.dig("metadata", "ownerReferences")).find { |owner| owner["kind"] == cronjob_kind.name }&.dig("name")
            return if name.blank?

            kind = cronjob_kind
            action = ResourceMap::Event::UPDATED
          end

          _provider, account, map_kind, external_id = Packs::Kubernetes.key_of(api.host, kind, item.dig("metadata", "namespace").presence || namespace, name)
          at = type == DELETED && item.dig("metadata", "deletionTimestamp") ? Time.iso8601(item.dig("metadata", "deletionTimestamp")) : Time.current
          ResourceMap::Event.new(id: "#{item.dig('metadata', 'uid')}@#{item.dig('metadata', 'resourceVersion')}", at: at, action: action,
                                 scope: ResourceMap::Scope.new(account: account, kind: map_kind, external_id: external_id))
        rescue ArgumentError
          nil
        end

        def cronjob_kind = Packs::Kubernetes::WORKLOADS.fetch(Packs::Kubernetes::CRONJOB)

        # A Warning event added or counted again, about the workload on the map it concerns. Its id carries the event's
        # version, so each repeat of a warning wakes the watches once.
        def warning_of(api, owners, namespace, type, item)
          return unless [ ADDED, MODIFIED ].include?(type) && item["type"] == Packs::Kubernetes::EVENT_WARNING

          involved = item["involvedObject"].to_h
          where = involved["namespace"].presence || item.dig("metadata", "namespace").presence || namespace
          kind, name = owners.workload(involved["kind"], where, involved["name"])
          return unless kind

          _provider, account, map_kind, external_id = Packs::Kubernetes.key_of(api.host, kind, where, name)
          ResourceMap::Event.new(id: "warning:#{item.dig('metadata', 'uid')}@#{item.dig('metadata', 'resourceVersion')}", at: Time.current,
                                 action: ResourceMap::Event::UPDATED, scope: ResourceMap::Scope.new(account: account, kind: map_kind, external_id: external_id))
        end

        # The list moved on past what the API server keeps, so everything the connection reaches is read again once.
        def full_read(kind, namespace, version)
          ResourceMap::Event.new(id: "gone:#{list_key(kind, namespace)}@#{version}", at: Time.current, action: ResourceMap::Event::UPDATED)
        end
      end

      # The workload on the map a warning's object belongs to: the object itself when it is a workload, and otherwise its
      # controller, read through ownerReferences up to a workload. A Job a CronJob made counts as the CronJob. Each object
      # is read at most once, and at most OWNER_READS in one watch.
      class OwnerReads
        OWNED = {
          "Pod" => "#{Packs::Kubernetes::CORE}/namespaces/%<namespace>s/pods/%<name>s",
          "ReplicaSet" => "#{Packs::Kubernetes::APPS}/namespaces/%<namespace>s/replicasets/%<name>s",
          "Job" => "#{Packs::Kubernetes::BATCH}/namespaces/%<namespace>s/jobs/%<name>s"
        }.freeze

        def initialize(api)
          @api = api
          @found = {}
          @reads = 0
        end

        def workload(kind_name, namespace, name)
          return if name.blank?

          @found.fetch([ kind_name, namespace, name ]) { @found[[ kind_name, namespace, name ]] = resolve(kind_name, namespace, name) }
        end

        private

        def resolve(kind_name, namespace, name)
          kind = Packs::Kubernetes::WORKLOADS.values.find { |each| each.name == kind_name }
          return owner_of(kind_name, namespace, name) unless kind
          return [ kind, name ] unless kind.key == Packs::Kubernetes::JOB

          job = read(kind_name, namespace, name)
          return unless job

          cronjob = Array(job.dig("metadata", "ownerReferences")).find { |owner| owner["kind"] == Packs::Kubernetes::WORKLOADS.fetch(Packs::Kubernetes::CRONJOB).name }
          cronjob ? [ Packs::Kubernetes::WORKLOADS.fetch(Packs::Kubernetes::CRONJOB), cronjob["name"] ] : [ kind, name ]
        end

        def owner_of(kind_name, namespace, name)
          return unless OWNED.key?(kind_name)

          owner = Array(read(kind_name, namespace, name)&.dig("metadata", "ownerReferences")).find { |each| each["controller"] }
          owner && workload(owner["kind"], namespace, owner["name"])
        end

        def read(kind_name, namespace, name)
          return if @reads >= OWNER_READS

          @reads += 1
          @api.get(format(OWNED.fetch(kind_name), namespace: Http.segment(namespace), name: Http.segment(name)))
        rescue KubernetesApi::NotFound, KubernetesApi::Forbidden
          nil
        end
      end
    end
  end
end
