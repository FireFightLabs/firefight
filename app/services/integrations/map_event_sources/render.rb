module Integrations
  module MapEventSources
    # Render's changes, sent to a webhook Firefight registers in the workspace with the connection's API key (spec, POST
    # /webhooks, api-docs.render.com/openapi/render-public-api-1.json). Render signs each delivery as Standard Webhooks
    # specifies (render.com/docs/webhooks, Communication protocol). Its payload holds only the event's type, when it
    # happened and the id of the service or datastore it is about (render.com/docs/webhooks, Request body), so the map
    # reads that one again. Webhooks need a Pro workspace or higher, and a Pro workspace has room for one.
    class Render < MapEventSource
      ID_HEADER = "webhook-id".freeze
      TIMESTAMP_HEADER = "webhook-timestamp".freeze
      SIGNATURE_HEADER = "webhook-signature".freeze
      # Each signature in the header is a version and a base64 HMAC-SHA256 of "<id>.<timestamp>.<body>", the key being the
      # secret after its prefix, base64 decoded, as Render's own receiver checks it with the standardwebhooks library
      # (render-examples/webhook-receiver, app.ts).
      SIGNATURE_VERSION = "v1".freeze
      SECRET_PREFIX = "whsec_".freeze
      # A delivery sent further from now than this is refused, the window Render's docs suggest for webhook-timestamp.
      TOLERANCE = 5.minutes
      WEBHOOK_NAME = "Firefight live updates".freeze

      # The event types that change what the map shows of a service (its deploy status and commit, whether it is
      # suspended, its plan and instances) or of a datastore (its status, plan and version), from the spec's list
      # (retrieve-event, type) and the docs' (render.com/docs/webhooks, Event types). A service and a datastore are each
      # named by data.serviceId. Render sends nothing when a service is created or deleted, so the sweep finds those.
      SERVICE_EVENTS = %w[
        build_started build_ended pre_deploy_started pre_deploy_ended deploy_started deploy_ended zero_downtime_redeploy_ended
        service_suspended service_resumed instance_count_changed autoscaling_ended plan_changed branch_deleted
      ].freeze
      POSTGRES_EVENTS = %w[postgres_created postgres_available postgres_unavailable postgres_restarted postgres_upgrade_succeeded].freeze
      KEY_VALUE_EVENTS = %w[key_value_available key_value_unhealthy key_value_config_restart].freeze
      EVENTS = (SERVICE_EVENTS + POSTGRES_EVENTS + KEY_VALUE_EVENTS).freeze
      ADDED = %w[postgres_created].freeze

      # Why Render may turn a registration down, said after its own words.
      PLAN_NOTE = "Render sends changes to webhooks on Pro workspaces and higher, and a Pro workspace has room for one, " \
                  "which Firefight leaves as it is".freeze

      # The most webhooks Render lets a Scale or Enterprise workspace have.
      MOST_WEBHOOKS = 100
      ONLY_WEBHOOK = "This Render workspace has no webhooks yet. On Render's Pro plan a workspace has room for one, so Firefight's " \
                     "would be its only webhook and the workspace could not add one of its own. Scale and Enterprise workspaces " \
                     "have room for 100.".freeze
      LAST_WEBHOOK = "This Render workspace has %<have>d webhooks and Render allows %<most>d, so Firefight's would be the last one " \
                     "the workspace can add.".freeze

      class << self
        def verify(raw_body:, headers:, secret:)
          id = headers[ID_HEADER].to_s
          stamp = headers[TIMESTAMP_HEADER].to_s
          return false if secret.blank? || id.empty? || !stamp.match?(/\A\d+\z/)
          return false if (Time.current.to_i - stamp.to_i).abs > TOLERANCE

          key = Base64.decode64(secret.to_s.delete_prefix(SECRET_PREFIX))
          expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, "#{id}.#{stamp}.#{raw_body}"))
          headers[SIGNATURE_HEADER].to_s.split.any? do |entry|
            version, signature = entry.split(",", 2)
            version == SIGNATURE_VERSION && signature.present? && ActiveSupport::SecurityUtils.secure_compare(signature, expected)
          end
        end

        # One event for a type the map reads again for, about the service or datastore it names. Its id is the same for
        # every retry of a notification, so a second delivery is a no-op.
        def events(payload, headers:)
          type = payload["type"].to_s
          about = payload.dig("data", "serviceId").presence
          return [] unless about && EVENTS.include?(type)

          kind = ResourceMap::KIND_DATABASE if (POSTGRES_EVENTS + KEY_VALUE_EVENTS).include?(type)
          [ ResourceMap::Event.new(id: payload.dig("data", "id").presence || headers[ID_HEADER], at: happened_at(payload["timestamp"]),
                                   action: ADDED.include?(type) ? ResourceMap::Event::ADDED : ResourceMap::Event::UPDATED,
                                   scope: ResourceMap::Scope.new(kind: kind, external_id: about)) ]
        end

        # Registers the workspace's webhook, or takes back one Firefight registered before at this connection's own
        # address, switching it on again if Render had switched it off. A webhook at any other address is never touched.
        def register(row, url:)
          api = api(row)
          owner = workspace_of(row)
          own = api.webhooks(owner).items.find { |webhook| webhook["url"] == url }
          own = api.enable_webhook(own["id"]) if own && !own["enabled"]
          own ||= api.create_webhook(owner, name: WEBHOOK_NAME, url: url, events: EVENTS)
          MapEventSource::Webhook.new(id: own["id"], secret: own["secret"])
        rescue RenderApi::Refused => error
          raise MapEventSource::Refused, Sentence.all(error, PLAN_NOTE)
        end

        # Render's API says nothing of a workspace's plan or how many webhooks it may have (spec, owner has no plan field,
        # and nothing else names one), so this goes by how many webhooks the workspace has and the documented limits,
        # one on Pro and 100 on Scale and Enterprise (render.com/docs/webhooks). A workspace with none may be on Pro,
        # where Firefight's would be its only one, and one with 99 would give Firefight its last, so a person decides.
        # With one to 98 of its own there is room to spare, or Render refuses for Pro, and Firefight's from before at
        # this address costs nothing.
        def confirmation_for(row, url:)
          webhooks = api(row).webhooks(workspace_of(row)).items
          return if webhooks.any? { |webhook| webhook["url"] == url }

          case webhooks.size
          when 0 then ONLY_WEBHOOK
          when MOST_WEBHOOKS - 1 then format(LAST_WEBHOOK, most: MOST_WEBHOOKS, have: webhooks.size)
          end
        rescue RenderApi::Refused => error
          raise MapEventSource::Refused, Sentence.all(error, PLAN_NOTE)
        end

        # A webhook already gone from Render is taken back all the same.
        def remove(row, webhook_id)
          api(row).delete_webhook(webhook_id)
        rescue RenderApi::NotFound
          nil
        end

        private

        def happened_at(timestamp)
          Time.iso8601(timestamp.to_s)
        rescue ArgumentError
          Time.current
        end

        def api(row)
          key = ConnectionSettings.of(row).credential(Packs::Render::API_KEY)
          raise Integrations::Error, "This connection has no Render API key. Reconnect it on the Integrations page." if key.blank?

          RenderApi.new(key)
        end

        def workspace_of(row)
          ConnectionSettings.of(row).field(Packs::Render::WORKSPACE) || raise(Integrations::Error, "This connection has no Render workspace. Reconnect it.")
        end
      end
    end
  end
end
