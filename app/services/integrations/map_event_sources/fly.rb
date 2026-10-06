module Integrations
  module MapEventSources
    # Fly.io sends no events for an organization's apps, so every five minutes Firefight lists its apps and each app's
    # machines, with each machine's state and updated_at (spec, GET /v1/apps and GET /v1/apps/{app_name}/machines,
    # docs.fly.io/api/machines/openapi.json), and an app whose apps list entry or machines changed since the last read is
    # read again. Fly allows one request a second for each action, with short bursts of three
    # (docs.fly.io/machines/api/working-with-machines-api, Rate limits), so the machine lists are read a second apart.
    class Fly < MapEventSource
      # A second between two machine lists keeps to Fly's one request a second for listing machines.
      PACE = 1.second

      class << self
        def verify(**) = false

        def events(_payload, headers:) = []

        # The cursor holds each app's fingerprint by name. The first read only takes them, so changes are followed from
        # now. An app whose machines could not be read keeps its fingerprint from before, and an app is taken as removed
        # only when the whole list was read without it.
        def poll(row, since:)
          api = Packs::Fly.client_for(row)
          listed = api.app_list(Packs::Fly.organization_for(row))
          before = cursor_of(since)
          now = {}
          events = []
          listed.items.each_with_index do |app, index|
            pause if index.positive?
            name = app["name"].to_s
            now[name] = fingerprint(api, app) || before&.dig(name)
            next if before.nil? || now[name].nil? || before[name] == now[name]

            events << event(name, now[name], before.key?(name) ? ResourceMap::Event::UPDATED : ResourceMap::Event::ADDED, row)
          end
          if before && !listed.incomplete?
            (before.keys - now.keys).each { |name| events << event(name, "gone-#{Time.current.to_i}", ResourceMap::Event::REMOVED, row) }
          elsif before
            now = before.merge(now)
          end
          MapEventSource::Polled.new(events: events, cursor: { "apps" => now.compact }.to_json)
        end

        def pause = sleep(PACE)

        private

        def cursor_of(since)
          return if since.blank?

          parsed = JSON.parse(since)
          parsed.is_a?(Hash) && parsed["apps"].is_a?(Hash) ? parsed["apps"] : nil
        rescue JSON::ParserError
          nil
        end

        # What the map shows of an app, from its status and its machines' states and when each last changed. nil when
        # its machines could not be read.
        def fingerprint(api, app)
          machines = api.machines(app["name"]).select { |machine| Packs::Fly.app_machine?(machine) }
          parts = machines.map { |machine| [ machine["id"], machine["state"], machine["updated_at"] ].join(":") }.sort
          Digest::SHA256.hexdigest([ app["status"], *parts ].to_json).first(16)
        rescue Integrations::RateLimited
          raise
        rescue FlyApi::NotFound
          "gone"
        rescue FlyApi::Error
          nil
        end

        def event(name, fingerprint, action, row)
          ResourceMap::Event.new(id: "#{name}@#{fingerprint}", at: Time.current, action: action,
                                 scope: ResourceMap::Scope.new(account: Packs::Fly.organization_for(row), kind: ResourceMap::KIND_SERVICE, external_id: name))
        end
      end
    end
  end
end
