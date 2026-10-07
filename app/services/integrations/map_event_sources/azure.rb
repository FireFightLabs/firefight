module Integrations
  module MapEventSources
    # Azure's changes, read every five minutes from each subscription's activity log with the connection's own service
    # principal (Activity Logs, List, Microsoft.Insights 2015-04-01, learn.microsoft.com/rest/api/monitor/activity-logs/list),
    # which the Reader role may read. Sending them instead would need an Event Grid system topic and subscription made in
    # the subscription, which Reader cannot make and which needs Firefight's address to answer Event Grid's validation, so
    # reading the log asks nothing more of an admin. Each event names the resource by its Resource Manager id, the
    # operation (operationName, such as Microsoft.Web/sites/write), how it ended (status) and its own eventDataId, unique
    # per event. An event is in the log 3 to 20 minutes after it happened (Azure Monitor activity log, Activity log
    # insights and retention), so each read reaches back past that.
    class Azure < MapEventSource
      # How far before the last read each read starts. One read twice carries the same eventDataId and is kept once.
      LAG = 30.minutes
      # An operation that ended. Started and Accepted say nothing has changed yet.
      ENDED = %w[Succeeded Failed].freeze
      DELETE = "/delete".freeze
      # A resource group or an Azure SQL server deleted takes what it holds with it, which only a sweep finds.
      HOLDERS_DELETED = %w[microsoft.resources/subscriptions/resourcegroups/delete microsoft.sql/servers/delete].freeze
      # A resource id's segments up to its name: "", subscriptions, the subscription, resourceGroups, the group,
      # providers, the namespace, the type and the name.
      SHORTEST_ID = 9

      class << self
        # Nothing is sent to the connection's address, so nothing that arrives there is Azure's.
        def verify(**) = false

        def events(_payload, headers:) = []

        # Each subscription's events since its own last read, as events about the app or database each names. A change to
        # something an app holds, such as a slot or its configuration, is about the app. A subscription's first read starts
        # from now.
        def poll(row, since:)
          known = ResourceMap::Resource.present.where(integration_environment: row, provider: Packs::Azure::PROVIDER_KEY).pluck(:external_id).index_by(&:downcase)
          poll_each_scope(row, since: since) { |subscription, cursor| poll_subscription(row, subscription, cursor, known) }
        end

        def limits = "Firefight reads Azure's activity log every 5 minutes, and Azure takes 3 to 20 minutes to add a change to it, " \
                     "so a change reaches the map within about 25 minutes."

        private

        def poll_subscription(row, subscription, since, known)
          now = Time.current
          return MapEventSource::Polled.new(events: [], cursor: now.utc.iso8601(6)) if since.blank?

          read = api(row, subscription).activity_log(Time.iso8601(since) - LAG, now)
          events = read.items.filter_map { |entry| event_of(subscription, entry, known) }
          MapEventSource::Polled.new(events: events, cursor: now.utc.iso8601(6))
        end

        def event_of(subscription, entry, known)
          return unless ENDED.include?(entry.dig("status", "value"))

          operation = entry.dig("operationName", "value").to_s.downcase
          at = time(entry["eventTimestamp"])
          return ResourceMap::Event.new(id: entry["eventDataId"], at: at, action: ResourceMap::Event::RESCOPE) if HOLDERS_DELETED.include?(operation)

          id = entry["resourceId"].to_s
          target = target_of(id)
          return unless target && target.subscription.casecmp?(subscription)

          own = target.id.casecmp?(id)
          action = own && operation.end_with?(DELETE) ? ResourceMap::Event::REMOVED : ResourceMap::Event::UPDATED
          # Azure writes an id's casing as it pleases, and the map keeps it as Resource Manager lists it.
          ResourceMap::Event.new(id: entry["eventDataId"], at: at, action: action,
                                 scope: ResourceMap::Scope.new(account: subscription, kind: Packs::Azure::KINDS.fetch(target.type),
                                                               external_id: known.fetch(target.id.downcase, target.id)))
        end

        # The app or database an id is, or holds it, by the shortest start of the id the pack reads as one.
        def target_of(id)
          segments = id.split("/")
          (SHORTEST_ID..segments.size).each do |length|
            target = Packs::Azure::Target.parse(segments.first(length).join("/"))
            return target if target
          end
          nil
        end

        def time(value)
          Time.iso8601(value.to_s)
        rescue ArgumentError
          Time.current
        end

        def api(row, subscription)
          settings = ConnectionSettings.of(row)
          tenant, client = settings.field(Packs::Azure::TENANT), settings.field(Packs::Azure::CLIENT)
          secret = settings.credential(Packs::Azure::SECRET)
          raise Integrations::Error, "This connection has no Azure service principal. Reconnect it on the Integrations page." if [ tenant, client, secret, subscription ].any?(&:blank?)

          AzureApi.new(tenant: tenant, client_id: client, client_secret: secret, subscription: subscription,
                       cloud: Packs::Azure.cloud_of(settings.region), token_cache: settings)
        end
      end
    end
  end
end
