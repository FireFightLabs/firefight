module Integrations
  module MapEventSources
    # Modal sends no events Firefight can register for: its only notifications go to a Slack channel a person links
    # (modal.com/docs/guide/slack-notifications), and its client has no webhook or change log. So every five minutes
    # Firefight lists the environment's apps, as modal app list does (AppList, py/modal/cli/app.py), and an app whose state
    # or deployed version moved since the last read is read again. Only deployed apps are on the map, so an app is followed
    # while it is deployed and until it leaves the list, and an ephemeral one a person runs and ends is not. How many
    # containers an app runs moves with its work, so it is left for the hourly sweep.
    class Modal < MapEventSource
      class << self
        def verify(**) = false

        def events(_payload, headers:) = []

        def limits = "Firefight lists Modal's apps every 5 minutes, so an app deployed, rolled back or stopped reaches the map within " \
                     "about 6 minutes. How many containers an app runs reaches the map at each hourly sweep."

        # The cursor holds each app's fingerprint by id. The first read only takes them, so changes are followed from then,
        # and an app that left the list is taken as removed.
        def poll(row, since:)
          before = cursor_of(since)
          followed = Packs::Modal.listed_apps(row).select { |app| app.state == Packs::Modal::DEPLOYED || before&.key?(app.app_id) }
          now = followed.to_h { |app| [ app.app_id, fingerprint(app) ] }
          events = before ? changes(before, now) : []
          MapEventSource::Polled.new(events: events, cursor: { "apps" => now }.to_json)
        rescue ModalApi::Refused => error
          raise MapEventSource::Refused, error.message
        end

        private

        def changes(before, now)
          moved = now.filter_map do |app_id, fingerprint|
            next if before[app_id] == fingerprint

            event(app_id, fingerprint, before.key?(app_id) ? ResourceMap::Event::UPDATED : ResourceMap::Event::ADDED)
          end
          moved + (before.keys - now.keys).map { |app_id| event(app_id, "gone-#{Time.current.to_i}", ResourceMap::Event::REMOVED) }
        end

        def cursor_of(since)
          return if since.blank?

          parsed = JSON.parse(since)
          parsed["apps"] if parsed.is_a?(Hash) && parsed["apps"].is_a?(Hash)
        rescue JSON::ParserError
          nil
        end

        # What the map shows of an app that is not its containers: its state, the version deployed and when it stopped.
        def fingerprint(app)
          lifecycle = app.metadata&.lifecycle
          Digest::SHA256.hexdigest([ app.state.to_s, lifecycle&.version, lifecycle&.deployed_at, app.stopped_at ].to_json).first(16)
        end

        def event(app_id, fingerprint, action)
          ResourceMap::Event.new(id: "#{app_id}@#{fingerprint}", at: Time.current, action: action,
                                 scope: ResourceMap::Scope.new(kind: ResourceMap::KIND_SERVICE, external_id: app_id))
        end
      end
    end
  end
end
