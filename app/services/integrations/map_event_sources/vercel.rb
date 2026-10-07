module Integrations
  module MapEventSources
    # Vercel's changes, sent to a webhook Firefight registers for the whole of each team the connection reaches with the connection's access token (spec,
    # createWebhook, openapi.vercel.sh). Vercel signs each delivery with an HMAC-SHA1 of the raw body in x-vercel-signature,
    # keyed by the secret it answers when the webhook is made (vercel.com/docs/webhooks/webhooks-api, Securing webhooks).
    # Each event names the project it is about, which the map reads again. Account webhooks are for Pro and Enterprise
    # teams, up to 20 a team (vercel.com/docs/webhooks, Account Webhooks).
    class Vercel < MapEventSource
      SIGNATURE_HEADER = "x-vercel-signature".freeze
      PRODUCTION = "production".freeze

      # Deployments change the production deployment's state and commit, which the map shows, so a preview's are left out
      # (payload.target is production or null for one).
      DEPLOYMENT_EVENTS = %w[deployment.created deployment.succeeded deployment.error deployment.canceled].freeze
      # Production moving to another deployment without a new one.
      PRODUCTION_EVENTS = %w[deployment.promoted deployment.rollback].freeze
      PROJECT_CREATED = "project.created".freeze
      PROJECT_REMOVED = "project.removed".freeze
      PROJECT_EVENTS = [ PROJECT_CREATED, PROJECT_REMOVED, "project.renamed" ].freeze
      # A setting changing changes where the project's settings point (payload.projectId, not payload.project.id).
      SETTING_EVENTS = %w[project.env-variable.created project.env-variable.updated project.env-variable.deleted].freeze
      # A domain joining a project is read with the project. One leaving it, moving, being renamed or redirected, or no
      # longer verified is read in a full sweep, since only reading every project says none serves it now.
      DOMAIN_ADDED_EVENTS = %w[project.domain.created project.domain.verified].freeze
      DOMAIN_CHANGED_EVENTS = %w[project.domain.updated project.domain.deleted project.domain.unverified project.domain.moved].freeze
      EVENTS = (DEPLOYMENT_EVENTS + PRODUCTION_EVENTS + PROJECT_EVENTS + SETTING_EVENTS + DOMAIN_ADDED_EVENTS + DOMAIN_CHANGED_EVENTS).freeze

      PLAN_NOTE = "Vercel sends changes to webhooks on Pro and Enterprise teams, up to 20 a team".freeze

      class << self
        def verify(raw_body:, headers:, secret:)
          return false if secret.blank?

          ActiveSupport::SecurityUtils.secure_compare(headers[SIGNATURE_HEADER].to_s, OpenSSL::HMAC.hexdigest("SHA1", secret, raw_body))
        end

        def events(payload, headers:)
          type = payload["type"].to_s
          body = payload["payload"].is_a?(Hash) ? payload["payload"] : {}
          # createdAt is in milliseconds since the epoch (vercel.com/docs/webhooks, Events).
          at = payload["createdAt"].is_a?(Numeric) ? Time.zone.at(payload["createdAt"] / 1000.0) : Time.current
          return [] unless EVENTS.include?(type)
          return [ event(payload, at, ResourceMap::Event::RESCOPE, ResourceMap::Scope.everything) ] if DOMAIN_CHANGED_EVENTS.include?(type)
          return [] if DEPLOYMENT_EVENTS.include?(type) && body["target"] != PRODUCTION

          project = SETTING_EVENTS.include?(type) ? body["projectId"] : body.dig("project", "id")
          return [] if project.blank?

          scope = ResourceMap::Scope.new(account: body.dig("team", "id"), kind: ResourceMap::KIND_SITE, external_id: project)
          [ event(payload, at, action_of(type), scope) ]
        end

        # Registers a webhook in each team the connection reaches, or in the token's own account when it names none. One
        # at this connection's own address is Firefight's from before, whose secret Vercel never shows again, so it is
        # deleted first. Vercel makes each webhook's secret, so they are kept one a line and a delivery signed with any
        # counts. A team the connection no longer reaches loses the webhook Firefight registered there. A webhook at any
        # other address is never touched.
        def register(row, url:)
          settings = ConnectionSettings.of(row)
          teams = settings.scopes
          return registered_in(row, nil, url) if teams.empty?

          registrations(row.map_events_webhook_id, settings).except(*teams).each { |team, webhook| forget(api(row, team), webhook) }
          made = teams.to_h { |team| [ team, registered_in(row, team, url) ] }
          MapEventSource::Webhook.new(id: made.transform_values(&:id).to_json, secret: made.values.filter_map(&:secret).uniq.join("\n").presence, scopes: teams)
        rescue VercelApi::Refused, VercelApi::PlanLimited => error
          raise MapEventSource::Refused, Sentence.all(error, PLAN_NOTE)
        end

        def limits = "Vercel's preview deployments are not on the map, so they bring no update. Everything else on the map follows Vercel's changes within about a minute."

        # Every team's webhook. One already gone from Vercel is taken back all the same.
        def remove(row, webhook_id)
          settings = ConnectionSettings.of(row)
          return forget(api(row, nil), webhook_id) if settings.chosen_scopes.empty?

          registrations(webhook_id, settings).each { |team, webhook| forget(api(row, team), webhook) }
        end

        private

        def event(payload, at, action, scope) = ResourceMap::Event.new(id: payload["id"], at: at, action: action, scope: scope)

        def action_of(type)
          case type
          when PROJECT_CREATED then ResourceMap::Event::ADDED
          when PROJECT_REMOVED then ResourceMap::Event::REMOVED
          when *DOMAIN_ADDED_EVENTS then ResourceMap::Event::LINKED
          else ResourceMap::Event::UPDATED
          end
        end

        def registered_in(row, team, url)
          api = api(row, team)
          api.webhooks.select { |webhook| webhook["url"] == url }.each { |webhook| api.delete_webhook(webhook["id"]) }
          created = api.create_webhook(url: url, events: EVENTS)
          MapEventSource::Webhook.new(id: created["id"], secret: created["secret"])
        end

        def forget(api, webhook)
          api.delete_webhook(webhook)
        rescue VercelApi::NotFound
          nil
        end

        def api(row, team)
          token = ConnectionSettings.of(row).credential(Packs::Vercel::API_TOKEN)
          raise Integrations::Error, "This connection has no Vercel access token. Reconnect it on the Integrations page." if token.blank?

          VercelApi.new(token, team)
        end
      end
    end
  end
end
