module Integrations
  module MapEventSources
    # Cloudflare sends no events Firefight can register for, so every five minutes it reads each account's audit log
    # (Audit Logs v2) through Cloudflare's own server, with the fixed script MapReaders::Cloudflare#changes runs on
    # execute, only when execute is switched on, recorded under the map sweep. Each write names the API path it
    # was made on (raw.uri), which says what changed: a zone, or a Worker, Pages project, bucket, database, namespace,
    # queue, Tunnel, pool or Hyperdrive configuration in an account. Reading the log needs Account Settings Read, and a
    # connection without it stays on the daily read, saying why.
    class Cloudflare < MapEventSource
      # Audit entries can be written after the change they record, so each read looks back this far, and an entry read
      # twice is kept once.
      LAG = 10.minutes
      API_PREFIX = %r{\A/client/v4}
      # An account's products by the path after /accounts/<id>, with what each is on the map. A queue's path holds its id
      # and the map keys it by name, so a change to one reads every queue of the account.
      ACCOUNT_PATHS = {
        "workers/scripts" => ResourceMap::KIND_WORKER, "pages/projects" => ResourceMap::KIND_SITE, "r2/buckets" => ResourceMap::KIND_BUCKET,
        "d1/database" => ResourceMap::KIND_DATABASE, "storage/kv/namespaces" => ResourceMap::KIND_KV_NAMESPACE, "queues" => ResourceMap::KIND_QUEUE,
        "cfd_tunnel" => ResourceMap::KIND_TUNNEL, "tunnels" => ResourceMap::KIND_TUNNEL, "load_balancers/pools" => ResourceMap::KIND_ORIGIN_POOL,
        "hyperdrive/configs" => ResourceMap::KIND_DATABASE_PROXY
      }.freeze
      KEYED_BY_NAME_ELSEWHERE = [ ResourceMap::KIND_QUEUE ].freeze
      # Writes that change data or start a session and nothing the map shows, such as a KV value, a D1 query, a cache
      # purge or a log tail.
      DATA_WRITES = %w[values bulk query raw export import purge_cache tails].freeze
      # Writes that change which hostnames are served by what, which only reading everything says in full: a DNS record,
      # Worker route or load balancer removed, a Worker custom domain, a Tunnel's routes, a Pages domain or an Access app.
      HOSTNAME_PATHS = [ %r{\Aworkers/domains}, %r{\Aaccess/}, %r{\Acfd_tunnel/[^/]+/configurations}, %r{\Apages/projects/[^/]+/domains} ].freeze
      ZONE_REMOVALS = %r{\A(dns_records|workers/routes|load_balancers)(/|\z)}
      DELETE = "DELETE".freeze
      POST = "POST".freeze
      AUDIT_NOTE = "Following Cloudflare's changes reads its audit log, which needs Account Settings Read on the connection".freeze

      class << self
        def verify(**) = false

        def events(_payload, headers:) = []

        def limits = "Firefight reads Cloudflare's audit log every 5 minutes, so a change reaches the map within about 6 minutes. A DNS record " \
                     "renamed keeps its old hostname on the map until the daily read."

        def poll(row, since:)
          before = Time.current
          return MapEventSource::Polled.new(events: [], cursor: before.utc.iso8601) if since.blank?

          changes = McpExecutor.map_events_reader(row).changes(since: start_of(since, before), before: before)
          if changes.refused.any?
            refused = changes.refused.map { |each| Sentence.join("Cloudflare refused the audit log of #{each['account']}", each["error"]) }
            raise MapEventSource::Refused, Sentence.all(*refused, AUDIT_NOTE)
          end

          events = changes.entries.filter_map { |entry| event_of(entry) }
          events += changes.unread.map { |account| full_read("unread:#{account}@#{before.to_i}", before) }
          MapEventSource::Polled.new(events: events, cursor: before.utc.iso8601)
        rescue RemoteReader::Refused => error
          raise MapEventSource::Refused, Sentence.all(error, AUDIT_NOTE)
        end

        private

        def start_of(since, before)
          Time.iso8601(since) - LAG
        rescue ArgumentError
          before - LAG
        end

        # The scope a write names, by its API path, or nil for one that changes nothing the map shows.
        def event_of(entry)
          path = URI.parse(entry["raw.uri"].to_s).path.to_s.sub(API_PREFIX, "")
          segments = path.split("/").compact_blank
          return if segments.any? { |segment| DATA_WRITES.include?(segment) }

          method = entry["raw.method"].to_s.upcase
          at = Time.iso8601(entry["action.time"].to_s)
          case segments.first
          when "zones" then zone_event(entry, segments.drop(1), method, at)
          when "accounts" then account_event(entry, segments.drop(2).join("/"), method, at)
          end
        rescue URI::InvalidURIError, ArgumentError
          nil
        end

        def zone_event(entry, segments, method, at)
          zone, *rest = segments
          return if zone.blank?
          return full_read(entry["id"], at) if method == DELETE && (rest.empty? || rest.join("/").match?(ZONE_REMOVALS))

          scope = ResourceMap::Scope.new(account: entry["account"], kind: ResourceMap::KIND_ZONE, external_id: zone)
          ResourceMap::Event.new(id: entry["id"], at: at, action: ResourceMap::Event::UPDATED, scope: scope)
        end

        def account_event(entry, path, method, at)
          return full_read(entry["id"], at) if HOSTNAME_PATHS.any? { |pattern| path.match?(pattern) }

          prefix, kind = ACCOUNT_PATHS.find { |each, _kind| path == each || path.start_with?("#{each}/") }
          return unless kind

          id = path.delete_prefix(prefix).split("/").compact_blank.first
          id = nil if KEYED_BY_NAME_ELSEWHERE.include?(kind)
          whole = path.delete_prefix(prefix).split("/").compact_blank.size == 1
          action = if method == DELETE && whole then ResourceMap::Event::REMOVED
          elsif method == POST && id.nil? then ResourceMap::Event::ADDED
          else ResourceMap::Event::UPDATED
          end
          scope = ResourceMap::Scope.new(account: entry["account"], kind: kind, external_id: id)
          ResourceMap::Event.new(id: entry["id"], at: at, action: action, scope: scope)
        end

        # A change only reading everything the connection reaches says in full.
        def full_read(id, at) = ResourceMap::Event.new(id: id, at: at, action: ResourceMap::Event::RESCOPE)
      end
    end
  end
end
