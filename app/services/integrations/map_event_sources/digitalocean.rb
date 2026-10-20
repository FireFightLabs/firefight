module Integrations
  module MapEventSources
    # DigitalOcean sends no webhook Firefight can register for an app, so every five minutes it reads the events of each
    # App Platform app the map has from this connection (apps_list_events, GET /v2/apps/{app_id}/events), each a
    # deployment or an autoscaling with the phase it is in (digitalocean/openapi, specification/resources/apps,
    # models/app_event.yml). An event new since the last read, or one whose phase moved, has the app read again, which
    # also wakes a watch on it.
    class Digitalocean < MapEventSource
      PROVIDER_KEY = Packs::Digitalocean::PROVIDER_KEY
      # The newest events one read takes of an app. An app that changed more often than this between two reads still
      # has its newest ones read.
      PER_APP = 20
      # The apps one poll reads, so a team with many stays inside DigitalOcean's 250 requests a minute. A team with more is
      # read in turns, each poll going on where the last stopped.
      BUDGET = 100

      class << self
        def verify(**) = false

        def events(_payload, headers:) = []

        def limits = "Firefight reads each app's deployments and autoscaling every 5 minutes, so a change reaches the map within about 6 " \
                     "minutes. A team with more than #{BUDGET} apps is read #{BUDGET} apps at a time, so a change there can take longer. " \
                     "A Droplet or a database changing, and an app added, reach the map at each hourly sweep."

        # The cursor holds, by app, a short key for each event the last read saw, and the app the next poll starts at. The
        # first read of an app only takes its keys, so changes are followed from then. An app whose events could not be
        # read keeps its keys from before, and one DigitalOcean no longer holds is read again so the map finds it gone.
        def poll(row, since:)
          api = api(row)
          apps = ResourceMap::Resource.where(integration_environment_id: row.id, provider: PROVIDER_KEY, kind: ResourceMap::KIND_SERVICE, removed_at: nil)
                                      .order(:external_id).pluck(:account, :external_id)
          before, start_at = cursor_of(since)
          ids = apps.map(&:last)
          start = ids.index(start_at) || 0
          turn = apps.rotate(start).first(budget)
          seen = (before || {}).slice(*ids)
          found = turn.flat_map do |account, id|
            listed = api.events(id, limit: PER_APP)
            keys = listed.map { |event| key_of(event) }
            news = before&.key?(id) ? listed.zip(keys).reject { |_event, key| before[id].include?(key) } : []
            seen[id] = keys
            news.map { |event, key| map_event(account, id, "#{event['id']}:#{phase_of(event)}", key, Telemetry.parse_time(event["created_at"])) }
          rescue Integrations::RateLimited
            raise
          rescue DigitaloceanApi::NotFound
            seen.delete(id)
            [ map_event(account, id, "#{id}:gone", "gone", Time.current) ]
          rescue DigitaloceanApi::Error
            []
          end
          following = ids.size > turn.size ? ids.rotate(start)[turn.size] : nil
          MapEventSource::Polled.new(events: found, cursor: { "apps" => seen, "next" => following }.compact.to_json)
        end

        def budget = BUDGET

        private

        def api(row)
          token = ConnectionSettings.of(row).credential(Packs::Digitalocean::API_TOKEN)
          raise Integrations::Error, "This connection has no DigitalOcean token. Reconnect it on the Integrations page." if token.blank?

          DigitaloceanApi.new(token)
        end

        # A deployment's phase, or an autoscaling's, which moves as it runs.
        def phase_of(event) = (event.dig("deployment", "phase") || event.dig("autoscaling", "phase")).to_s

        def key_of(event) = Digest::SHA256.hexdigest("#{event['id']}:#{phase_of(event)}").first(16)

        def map_event(account, app_id, provider_id, key, at)
          ResourceMap::Event.new(id: "#{provider_id}@#{key}", at: at || Time.current, action: ResourceMap::Event::UPDATED,
                                 scope: ResourceMap::Scope.new(account: account, kind: ResourceMap::KIND_SERVICE, external_id: app_id))
        end

        # The keys by app and the app to start at, nil and nil the first time.
        def cursor_of(since)
          return [ nil, nil ] if since.blank?

          parsed = JSON.parse(since)
          parsed.is_a?(Hash) && parsed["apps"].is_a?(Hash) ? [ parsed["apps"], parsed["next"] ] : [ nil, nil ]
        rescue JSON::ParserError
          [ nil, nil ]
        end
      end
    end
  end
end
