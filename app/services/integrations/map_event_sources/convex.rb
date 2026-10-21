module Integrations
  module MapEventSources
    # Convex's changes, sent by a webhook log stream Firefight adds to the deployment with its deploy key (create_log_stream,
    # deployment-openapi.json in get-convex/convex-backend). It subscribes to the audit_log topic only, which records each
    # push, pause, unpause and other change to the deployment, and not to function executions or console lines. Convex
    # signs each request with an HMAC-SHA256 hex digest of the body in x-webhook-signature, after sha256=, and sends a JSON
    # array of events, each with its topic and time in milliseconds (docs.convex.dev/production/integrations/log-streams).
    # Log streams need a Convex Pro plan, and a deployment has one of each kind, so Firefight's would be its only webhook
    # stream and a person decides first.
    class Convex < MapEventSource
      SIGNATURE_HEADER = "x-webhook-signature".freeze
      SIGNATURE_PREFIX = "sha256=".freeze
      AUDIT_LOG = "audit_log".freeze
      TOPICS = [ AUDIT_LOG ].freeze
      # Convex's docs suggest refusing an event older than five minutes, against a replay.
      TOLERANCE = 5.minutes
      ONLY_STREAM = "Convex allows one webhook log stream per deployment, so your team could not add its own while this is on. " \
                    "Log streams need Convex's Pro plan.".freeze
      PLAN_NOTE = "Convex sends log streams on its Pro plan, and a deployment can have one webhook log stream".freeze
      TAKEN = "This deployment already sends a webhook log stream to another address, and Convex allows one".freeze
      REFUSED = /\AConvex answered 4\d\d/

      class << self
        def verify(raw_body:, headers:, secret:)
          signature = headers[SIGNATURE_HEADER].to_s
          return false if secret.blank? || !signature.start_with?(SIGNATURE_PREFIX)

          ActiveSupport::SecurityUtils.secure_compare(signature.delete_prefix(SIGNATURE_PREFIX), OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, raw_body))
        end

        # One event for each audit log entry, about the deployment it names. An entry has no id of its own and a retry
        # repeats it, so a digest of it makes a second delivery a no-op. An entry older than TOLERANCE is dropped.
        def events(payload, headers:)
          Array(payload).filter_map do |entry|
            next unless entry.is_a?(Hash) && entry["topic"] == AUDIT_LOG

            name = entry.dig("convex", "deployment_name").presence
            at = entry["timestamp"].is_a?(Numeric) ? Time.zone.at(entry["timestamp"] / 1000.0) : nil
            next unless name && at && at > TOLERANCE.ago

            ResourceMap::Event.new(id: "convex-#{Digest::SHA256.hexdigest(entry.to_json)}", at: at, action: ResourceMap::Event::UPDATED,
                                   scope: ResourceMap::Scope.new(kind: ResourceMap::KIND_SERVICE, external_id: name))
          end
        end

        def limits = "Convex says when code is pushed to the deployment, it is paused or unpaused, or its settings change. What " \
                     "its functions print stays in its logs, which Firefight reads when asked."

        def turn_on_words = "Firefight adds a webhook log stream to this Convex deployment, so a push, a pause or a settings change " \
                            "reaches Firefight within about a minute."

        def turn_off_words = "Firefight removes its webhook log stream from this Convex deployment, so your team can add its own."

        # Firefight's own stream from before at this address is kept, and a webhook stream at another address is the
        # team's, which Convex allows only one of, so it is never replaced.
        def register(row, url:)
          api = api(row)
          own = api.log_streams.find { |stream| webhook?(stream) && stream["url"] == url }
          return MapEventSource::Webhook.new(id: own["id"], secret: own["hmacSecret"]) if own
          raise MapEventSource::Refused, Sentence.of(TAKEN) if api.log_streams.any? { |stream| webhook?(stream) }

          made = api.create_webhook_stream(url: url, topics: TOPICS)
          MapEventSource::Webhook.new(id: made["id"], secret: made["hmacSecret"])
        rescue ConvexApi::Error => error
          raise unless error.message.match?(REFUSED)

          raise MapEventSource::Refused, Sentence.all(error, PLAN_NOTE)
        end

        # Asked only while there is no webhook stream yet, since one at another address refuses the registration.
        def confirmation_for(row, url:)
          streams = api(row).log_streams.select { |stream| webhook?(stream) }
          ONLY_STREAM if streams.empty?
        rescue ConvexApi::Error => error
          raise unless error.message.match?(REFUSED)

          raise MapEventSource::Refused, Sentence.all(error, PLAN_NOTE)
        end

        def remove(row, webhook_id)
          api(row).delete_log_stream(webhook_id)
        rescue ConvexApi::Error => error
          raise unless error.message.start_with?("Convex answered 404")
        end

        private

        def webhook?(stream) = stream.is_a?(Hash) && stream["logStreamType"] == ConvexApi::WEBHOOK_STREAM

        def api(row)
          settings = ConnectionSettings.of(row)
          key = settings.credential(Packs::Convex::DEPLOY_KEY)
          url = settings.field(Packs::Convex::DEPLOYMENT_URL).to_s.chomp("/")
          raise Integrations::Error, "This connection has no Convex deploy key. Reconnect it on the Integrations page." if key.blank?
          # The key goes only to a deployment Convex hosts, as the pack sends it.
          raise Integrations::Error, "This connection's Convex deployment URL does not end in convex.cloud. Reconnect it." unless url.match?(Packs::Convex::CLOUD_URL)

          ConvexApi.new(url, key)
        end
      end
    end
  end
end
