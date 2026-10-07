module Integrations
  module MapEventSources
    # Railway's changes, sent to a webhook Firefight registers on each of the connection's projects with its token. A project's
    # webhook is a notification rule with a webhook channel (schema, Mutation.notificationRuleCreate, and the config
    # { type: "webhook", url, headers } Railway's own dashboard sends). Railway does not sign its deliveries and suggests a
    # custom header with a secret value instead (docs, content/docs/observability/webhooks.md, Verifying the sender), so
    # Firefight sends one of its own and checks it in constant time. A webhook covers every environment in the project,
    # and its payload names the service it is about (resource.service.id), which the map reads again.
    class Railway < MapEventSource
      SECRET_HEADER = "X-Firefight-Webhook-Secret".freeze

      # A project's webhook can follow deployment, monitor and volume alert events (Railway's dashboard,
      # PROJECT_WEBHOOK_EVENT_TYPES, Object.action as the docs write Deployment.failed). Every deployment status changes
      # what the map shows of a service, its status and commit. Monitor and volume alerts change nothing the map reads,
      # and Railway sends nothing when a service is created, renamed or deleted, or its variables change, so the sweep
      # finds those.
      DEPLOYMENT_ACTIONS = %w[building deploying deployed redeployed failed crashed oom_killed slept resumed restarted removed waiting needs_approval queued].freeze
      EVENTS = DEPLOYMENT_ACTIONS.map { |action| "Deployment.#{action}" }.freeze

      class << self
        def verify(raw_body:, headers:, secret:)
          return false if secret.blank?

          ActiveSupport::SecurityUtils.secure_compare(headers[SECRET_HEADER].to_s, secret.to_s)
        end

        # One event about the service a deployment belongs to, in the environment it ran in. Railway's payload has no id
        # of its own, and a retry sends the same body (docs, Delivery), so a digest of the body makes a retry a no-op.
        def events(payload, headers:)
          type = payload["type"].to_s
          resource = payload["resource"].is_a?(Hash) ? payload["resource"] : {}
          service = resource.dig("service", "id").presence
          return [] unless EVENTS.include?(type) && service

          # The connection's account is its project and environment, as the pack writes it.
          project, environment = resource.dig("project", "id"), resource.dig("environment", "id")
          account = "#{project}/#{environment}" if project.present? && environment.present?
          [ ResourceMap::Event.new(id: "railway-#{Digest::SHA256.hexdigest(payload.to_json)}", at: happened_at(payload["timestamp"]),
                                   action: ResourceMap::Event::UPDATED, scope: ResourceMap::Scope.new(account: account, external_id: service)) ]
        end

        # Registers a webhook on each project the connection reaches, every one with the same secret of Firefight's own in
        # its header. One at this connection's own address is Firefight's from before, whose header Railway never shows
        # again, so it is given the new secret. A project the connection no longer reaches loses the webhook Firefight
        # registered there. A webhook at any other address is never touched. The id is each project's rule, by project.
        def register(row, url:)
          api = api(row)
          secret = SecureRandom.hex(32)
          headers = { SECRET_HEADER => secret }
          projects = ConnectionSettings.of(row).scopes
          raise Integrations::Error, "This connection reaches no Railway project. Choose one on the Integrations page." if projects.empty?

          rules = registered(row.map_events_webhook_id, ConnectionSettings.of(row))
          rules.except(*projects).each_value { |rule| forget(api, rule) }
          made = projects.to_h do |project|
            workspace = api.project(project)&.dig("workspaceId") || raise(Integrations::Error, "Railway did not say which workspace project #{project} is in.")
            own = api.notification_rules(workspace, project).find { |rule| at?(rule, url) }
            rule = own ? api.update_webhook(own["id"], url: url, events: EVENTS, headers: headers) : api.create_webhook(workspace, project, url: url, events: EVENTS, headers: headers)
            [ project, rule["id"] ]
          end
          MapEventSource::Webhook.new(id: made.to_json, secret: secret, scopes: projects)
        rescue RailwayApi::Refused => error
          raise MapEventSource::Refused, error.message
        end

        def limits = "Railway says when a deployment changes status. A service added, renamed or removed, and a change to its variables, " \
                     "reach the map at each hourly sweep."

        # Every project's webhook. One already gone from Railway is taken back all the same.
        def remove(row, webhook_id)
          api = api(row)
          registered(webhook_id, ConnectionSettings.of(row)).each_value { |rule| forget(api, rule) }
        end

        private

        def at?(rule, url) = Array(rule["channels"]).any? { |channel| channel.dig("config", "url") == url }

        def happened_at(timestamp)
          Time.iso8601(timestamp.to_s)
        rescue ArgumentError
          Time.current
        end

        def api(row)
          token = ConnectionSettings.of(row).credential(Packs::Railway::API_TOKEN)
          raise Integrations::Error, "This connection has no Railway token. Reconnect it on the Integrations page." if token.blank?

          RailwayApi.new(token)
        end

        # The rule registered on each project, by project. One registered before a connection read several projects is
        # its one project's.
        def registered(webhook_id, settings)
          return {} if webhook_id.blank?

          parsed = JSON.parse(webhook_id)
          parsed.is_a?(Hash) ? parsed : { settings.chosen_scopes.first => webhook_id }
        rescue JSON::ParserError
          { settings.chosen_scopes.first => webhook_id }
        end

        def forget(api, rule)
          api.delete_webhook(rule)
        rescue RailwayApi::NotFound
          nil
        end
      end
    end
  end
end
