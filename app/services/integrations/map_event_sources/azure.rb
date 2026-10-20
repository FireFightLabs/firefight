module Integrations
  module MapEventSources
    # Azure's changes, read two ways on the same connection.
    #
    # Every connection reads each subscription's activity log every five minutes with its own service principal
    # (Activity Logs, List, Microsoft.Insights 2015-04-01, learn.microsoft.com/rest/api/monitor/activity-logs/list),
    # which the Reader role may read. Each event names the resource by its Resource Manager id, the operation
    # (operationName, such as Microsoft.Web/sites/write), how it ended (status) and its own eventDataId, unique per event.
    # An event is in the log 3 to 20 minutes after it happened (Azure Monitor activity log, Activity log insights and
    # retention), so each read reaches back past that.
    #
    # A person may also turn on Event Grid, which sends each change as it happens. Firefight then subscribes the
    # connection's address to each subscription's resource events, an event subscription at the subscription's scope
    # (Event Subscriptions, Create Or Update, Microsoft.EventGrid 2025-02-15), for which Event Grid makes the
    # subscription's system topic itself and deletes it with the last event subscription (Event Grid, System topics).
    # That needs Microsoft.EventGrid/EventSubscriptions/Write on the subscription, which the EventGrid EventSubscription
    # Contributor role holds (Event Grid, Authorize access to Event Grid resources), and Microsoft.EventGrid registered
    # on it. Event Grid confirms the address first with a SubscriptionValidationEvent answered with its validationCode
    # (Event Grid, Endpoint validation with Event Grid events schema), and sends every delivery with a secret static
    # header Firefight made (Event Grid, Delivery properties). Its events name the resource in data.resourceUri and the
    # operation in data.operationName (Azure subscription as an Event Grid source).
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

      GRID_VERSION = "2025-02-15".freeze
      PROVIDERS_VERSION = "2021-04-01".freeze
      GRID_PROVIDER = "Microsoft.EventGrid".freeze
      REGISTERED = "Registered".freeze
      # An event subscription's name, 3 to 64 letters and digits.
      SUBSCRIPTION_NAME = "firefightliveupdates".freeze
      KEY_HEADER = "x-firefight-key".freeze
      # The resource events that say something changed (Azure subscription as an Event Grid source, Event types).
      GRID_EVENTS = %w[Microsoft.Resources.ResourceWriteSuccess Microsoft.Resources.ResourceDeleteSuccess Microsoft.Resources.ResourceActionSuccess].freeze
      GRID_DELETED = "Microsoft.Resources.ResourceDeleteSuccess".freeze
      VALIDATION = "Microsoft.EventGrid.SubscriptionValidationEvent".freeze
      # An event subscription is made once Event Grid confirmed the address, so its state is read this long, every
      # GRID_POLL seconds, before it is left to finish on its own.
      GRID_WAIT = 25
      GRID_POLL = 5
      GRID_FAILED = %w[Failed Canceled AwaitingManualAction].freeze
      GRID_ROLE = "EventGrid EventSubscription Contributor".freeze

      class << self
        # Every delivery carries the secret header Firefight gave the event subscription. The key is compared as digests,
        # so the comparison takes as long whatever was sent.
        def verify(raw_body:, headers:, secret:)
          return false if secret.blank?

          ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.digest(headers[KEY_HEADER].to_s), Digest::SHA256.digest(secret))
        end

        # Event Grid asks the address to confirm itself once, and is answered with the code it sent, at once.
        def handshake(payload, headers:)
          validation = Array.wrap(payload).find { |event| event.is_a?(Hash) && event["eventType"] == VALIDATION }
          { "validationResponse" => validation.dig("data", "validationCode") } if validation&.dig("data", "validationCode").present?
        end

        # Each resource event as the poll reads its activity log entry, about the app or database it names. A resource
        # group or SQL server deleted is swept, since what it held went with it.
        def events(payload, headers:)
          Array.wrap(payload).filter_map do |event|
            next unless event.is_a?(Hash) && GRID_EVENTS.include?(event["eventType"])

            data = event["data"].is_a?(Hash) ? event["data"] : {}
            at = time(event["eventTime"])
            operation = data["operationName"].to_s.downcase
            next ResourceMap::Event.new(id: event["id"], at: at, action: ResourceMap::Event::RESCOPE) if HOLDERS_DELETED.include?(operation)

            id = data["resourceUri"].presence || event["subject"].to_s
            target = target_of(id)
            next unless target

            removed = event["eventType"] == GRID_DELETED && target.id.casecmp?(id)
            ResourceMap::Event.new(id: event["id"], at: at, action: removed ? ResourceMap::Event::REMOVED : ResourceMap::Event::UPDATED,
                                   scope: ResourceMap::Scope.new(account: target.subscription, kind: Packs::Azure::KINDS.fetch(target.type), external_id: target.id))
          end
        end

        # Each subscription's events since its own last read, as events about the app or database each names. A change to
        # something an app holds, such as a slot or its configuration, is about the app. A subscription's first read starts
        # from now.
        def poll(row, since:)
          known = ResourceMap::Resource.present.where(integration_environment: row, provider: Packs::Azure::PROVIDER_KEY).pluck(:external_id).index_by(&:downcase)
          poll_each_scope(row, since: since) { |subscription, cursor| poll_subscription(row, subscription, cursor, known) }
        end

        def limits = "Firefight reads Azure's activity log every 5 minutes, and Azure takes 3 to 20 minutes to add a change to it, " \
                     "so a change reaches the map within about 25 minutes. With Event Grid turned on, a change arrives within about a minute."

        # Turning Event Grid on is always a person's choice, since it needs a role the connection was not asked for.
        def confirmation_for(row, url:)
          "Firefight subscribes this connection to each subscription's resource changes through Event Grid, so a change reaches the map " \
            "within about a minute. Azure makes an Event Grid system topic for the subscription to send them. The service principal needs the #{GRID_ROLE} role on each subscription, and Microsoft.EventGrid " \
            "registered as a resource provider there. The activity log is still read every 5 minutes."
        end

        # An event subscription at each subscription's scope, made or made again at this connection's address with the
        # secret header, and followed until Event Grid confirmed the address. A subscription the connection no longer
        # reaches loses the one Firefight made there. The secret is kept before Event Grid's confirmation arrives, since it
        # carries the header too.
        def register(row, url:)
          settings = ConnectionSettings.of(row)
          subscriptions = settings.scopes
          raise Integrations::Error, "This connection reaches no Azure subscription. Choose one on the Integrations page." if subscriptions.empty?

          registrations(row.map_events_webhook_id, settings).except(*subscriptions).each { |subscription, path| forget(api(row, subscription), path) }
          secret = row.map_events_secret.presence || SecureRandom.hex(32)
          row.update!(map_events_secret: secret)
          made = subscriptions.to_h { |subscription| [ subscription, subscribe(api(row, subscription), subscription, url, secret) ] }
          MapEventSource::Webhook.new(id: made.to_json, secret: secret, scopes: subscriptions)
        end

        # Every event subscription Firefight made, which takes the system topic Event Grid made for it with it. One
        # already gone is taken back all the same.
        def remove(row, webhook_id)
          registrations(webhook_id, ConnectionSettings.of(row)).each { |subscription, path| forget(api(row, subscription), path) }
        end

        def turn_off_words = "Firefight removes its Event Grid subscription, and Azure removes the system topic it made for it. " \
                             "The activity log is still read every 5 minutes."

        private

        def subscribe(api, subscription, url, secret)
          registered!(api, subscription)
          path = "/subscriptions/#{api.segment(subscription)}/providers/#{GRID_PROVIDER}/eventSubscriptions/#{SUBSCRIPTION_NAME}"
          api.put(path, GRID_VERSION, body(url, secret))
          confirmed!(api, path, subscription)
          path
        rescue AzureApi::Forbidden => error
          raise Integrations::Error, Sentence.join("The service principal may not subscribe to subscription #{subscription}'s changes. Give it " \
                                                   "the #{GRID_ROLE} role on the subscription", error)
        end

        def body(url, secret)
          {
            "properties" => {
              "destination" => {
                "endpointType" => "WebHook",
                "properties" => {
                  "endpointUrl" => url, "maxEventsPerBatch" => 1,
                  "deliveryAttributeMappings" => [ { "name" => KEY_HEADER, "type" => "Static", "properties" => { "value" => secret, "isSecret" => true } } ]
                }
              },
              "filter" => { "includedEventTypes" => GRID_EVENTS },
              "eventDeliverySchema" => "EventGridSchema"
            }
          }
        end

        # Microsoft.EventGrid must be registered on the subscription before anything can subscribe to it (Resource
        # providers and types), which needs a role the connection is not asked for, so a person does it.
        def registered!(api, subscription)
          state = api.get("/subscriptions/#{api.segment(subscription)}/providers/#{GRID_PROVIDER}", PROVIDERS_VERSION)["registrationState"]
          return if state == REGISTERED

          raise Integrations::Error, "#{GRID_PROVIDER} is not registered on subscription #{subscription}. Register it in the Azure portal, under the " \
                                     "subscription's Resource providers, then turn live updates on again."
        end

        # Event Grid confirms the address before it makes the subscription, so its state says whether that worked. One
        # still being made after GRID_WAIT is left to finish.
        def confirmed!(api, path, subscription)
          (GRID_WAIT / GRID_POLL).times do
            state = api.get(path, GRID_VERSION).dig("properties", "provisioningState").to_s
            return if state == "Succeeded"

            if GRID_FAILED.include?(state)
              forget(api, path)
              raise Integrations::Error, "Event Grid could not confirm Firefight's address for subscription #{subscription}, so nothing was " \
                                         "subscribed. Check that Firefight's address is reachable from Azure, then turn live updates on again."
            end
            pause(GRID_POLL)
          end
        end

        def forget(api, path)
          api.delete(path, GRID_VERSION)
        rescue AzureApi::NotFound
          nil
        end

        def pause(seconds) = sleep(seconds)

        def poll_subscription(row, subscription, since, known)
          now = Time.current
          return MapEventSource::Polled.new(events: [], cursor: now.utc.iso8601(6)) if since.blank?

          read = api(row, subscription).activity_log(Time.iso8601(since) - LAG, now)
          events = read.items.filter_map { |entry| event_of(subscription, entry, known) }
          # A log longer than one read takes is swept in full, since the changes past the cut are not read.
          events << busy(subscription, now) if read.incomplete?
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

        def busy(subscription, now)
          ResourceMap::Event.new(id: "activity-log-busy #{subscription} #{now.utc.iso8601(6)}", at: now, action: ResourceMap::Event::UPDATED,
                                 scope: ResourceMap::Scope.everything)
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
