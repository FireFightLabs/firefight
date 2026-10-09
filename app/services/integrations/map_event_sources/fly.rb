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
      # The apps whose machines one poll reads, about four minutes at PACE, so a poll ends inside the poll job's ten
      # minute concurrency window. An organization with more is read in turns, each poll going on where the last stopped.
      BUDGET = 240
      # An app listed but whose machines have not been read yet, which says nothing when they first are.
      UNREAD = "unread".freeze

      class << self
        def verify(**) = false

        def events(_payload, headers:) = []

        def limits = "Firefight reads each app's machines every 5 minutes, so an app changing reaches the map within about 6 minutes. An " \
                     "organization with more than #{BUDGET} apps is read #{BUDGET} apps at a time, so a change there can take longer. A change " \
                     "to an app's certificates or Managed Postgres clusters reaches the map at each hourly sweep."

        # The cursor holds each app's fingerprint by name, and the app the next poll starts at. The first read of an app
        # only takes its fingerprint, so changes are followed from then. An app whose machines could not be read keeps
        # its fingerprint from before, and an app is taken as removed only when the whole list was read without it.
        def poll(row, since:)
          api = Packs::Fly.client_for(row)
          listed = api.app_list(Packs::Fly.organization_for(row))
          before, start_at = cursor_of(since)
          names = listed.items.map { |app| app["name"].to_s }
          start = names.index(start_at) || 0
          turn = listed.items.rotate(start).first(budget)
          now = names.index_with { |name| before&.dig(name) }
          turn.each_with_index do |app, index|
            pause if index.positive?
            name = app["name"].to_s
            now[name] = fingerprint(api, app) || before&.dig(name)
          end
          events = changes(row, before, now)
          now.transform_values! { |fingerprint| fingerprint || UNREAD }
          if before && !listed.incomplete?
            (before.keys - names).each { |name| events << event(name, "gone-#{Time.current.to_i}", ResourceMap::Event::REMOVED, row) }
          elsif before
            now = before.merge(now)
          end
          following = names.size > turn.size ? names.rotate(start)[turn.size] : nil
          MapEventSource::Polled.new(events: events, cursor: { "apps" => now, "next" => following }.compact.to_json)
        end

        def budget = BUDGET

        def pause = sleep(PACE)

        private

        # An app new to the list is added whether or not its machines were read yet. One whose fingerprint moved is
        # updated, unless the one before was only UNREAD.
        def changes(row, before, now)
          return [] if before.nil?

          now.filter_map do |name, fingerprint|
            if !before.key?(name)
              event(name, fingerprint || "new-#{Time.current.to_i}", ResourceMap::Event::ADDED, row)
            elsif fingerprint && before[name] != UNREAD && before[name] != fingerprint
              event(name, fingerprint, ResourceMap::Event::UPDATED, row)
            end
          end
        end

        # The fingerprints by app and the app to start at, nil and nil the first time.
        def cursor_of(since)
          return [ nil, nil ] if since.blank?

          parsed = JSON.parse(since)
          parsed.is_a?(Hash) && parsed["apps"].is_a?(Hash) ? [ parsed["apps"], parsed["next"] ] : [ nil, nil ]
        rescue JSON::ParserError
          [ nil, nil ]
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
