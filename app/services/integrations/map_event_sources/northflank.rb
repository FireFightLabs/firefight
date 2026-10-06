module Integrations
  module MapEventSources
    # Northflank's changes, sent to a webhook notification integration Firefight adds with the connection's API token,
    # restricted to the connected project (@northflank/js-client, CreateNotificationData, POST /v1/integrations/notifications).
    # Northflank sends the integration's secret as it is in X-Northflank-Notification-Integration-Token, the event's id in
    # X-Northflank-Notification-Integration-Event-Id, and a body of the event's type and data, which names the service,
    # addon or job it is about (northflank.com/docs/v1/application/observe/configure-notification-integrations, Webhook
    # secrets and Request format). The secret is compared, not a signature checked, so the event id is what makes a replay a
    # no-op. Adding one needs the token's role to read, create and delete notification integrations.
    class Northflank < MapEventSource
      TOKEN_HEADER = "x-northflank-notification-integration-token".freeze
      EVENT_ID_HEADER = "x-northflank-notification-integration-event-id".freeze
      # An integration's events are named with this prefix when it is made, and a delivery names its event without it, as
      # build:start for trigger:build:start (CreateNotificationData events, and Request format's example).
      TRIGGER = "trigger:".freeze

      # What changes a service as the map shows it (its deploy status and commit, its build status and its instances), an
      # addon (its status, which is backing up while a backup runs) and a job, each read again from the id the event names.
      SERVICE_EVENTS = %w[
        service:deployment:status-update service:autoscaling:event build:start build:success build:failure build:abort
        infrastructure:service:container-crash
      ].freeze
      ADDON_EVENTS = %w[addon-backup:start addon-backup:success addon-backup:failure addon-backup:abort infrastructure:addon:container-crash].freeze
      JOB_EVENTS = %w[job-run:start job-run:success job-run:failure job-run:abort job-run:terminate infrastructure:job:container-crash].freeze
      EVENTS = (SERVICE_EVENTS + ADDON_EVENTS + JOB_EVENTS).freeze
      KINDS = { "service" => nil, "addon" => ResourceMap::KIND_DATABASE, "job" => ResourceMap::KIND_JOB }.freeze
      WEBHOOK_NAME = "Firefight live updates".freeze

      PERMISSION_NOTE = "Firefight follows a Northflank project through a webhook notification integration, which the API token's role " \
                        "can add only with Notifications Read, Create and Delete (Account, Observability)".freeze

      class << self
        def verify(raw_body:, headers:, secret:)
          secret.present? && ActiveSupport::SecurityUtils.secure_compare(headers[TOKEN_HEADER].to_s, secret)
        end

        # One event about the service, addon or job the data names. A service's id may be a build service's, so its kind
        # is left for the re-read to say.
        def events(payload, headers:)
          type = payload["event"].to_s.delete_prefix(TRIGGER)
          return [] unless EVENTS.include?(type)

          data = payload["data"].is_a?(Hash) ? payload["data"] : {}
          about, kind = KINDS.filter_map { |key, each| [ data.dig(key, "id"), each ] if data.dig(key, "id").present? }.first
          return [] unless about

          [ ResourceMap::Event.new(id: headers[EVENT_ID_HEADER].presence, at: Time.current, action: ResourceMap::Event::UPDATED,
                                   scope: ResourceMap::Scope.new(kind: kind, external_id: about)) ]
        end

        # Adds the project's integration, deleting first one Firefight added before at this connection's own address, whose
        # secret Northflank never shows again. An integration at any other address is never touched.
        def register(row, url:)
          api = api(row)
          api.notifications.items.select { |integration| integration["webhook"] == url }.each { |integration| api.delete_notification(integration["id"]) }
          secret = SecureRandom.hex(32)
          project = project_of(row)
          created = api.create_notification(name: "#{WEBHOOK_NAME} #{project} #{row.map_events_token.to_s.first(6)}", url: url, secret: secret,
                                            events: EVENTS.map { |event| "#{TRIGGER}#{event}" }, projects: [ project ])
          MapEventSource::Webhook.new(id: created["id"], secret: secret)
        rescue NorthflankApi::Refused => error
          raise MapEventSource::Refused, Sentence.all(error, PERMISSION_NOTE)
        end

        # An integration already gone from Northflank is taken back all the same.
        def remove(row, webhook_id)
          api(row).delete_notification(webhook_id)
        rescue NorthflankApi::NotFound
          nil
        end

        def limits = "Northflank says when a service deploys or builds, a database backs up and a job runs. A service, database or job " \
                     "added or removed, and a change to its settings, reach the map at each hourly sweep."

        private

        def api(row)
          token = ConnectionSettings.of(row).credential(Packs::Northflank::API_TOKEN)
          raise Integrations::Error, "This connection has no Northflank token. Reconnect it on the Integrations page." if token.blank?

          NorthflankApi.new(token)
        end

        def project_of(row)
          ConnectionSettings.of(row).field(Packs::Northflank::PROJECT) || raise(Integrations::Error, "This connection has no Northflank project. Reconnect it.")
        end
      end
    end
  end
end
