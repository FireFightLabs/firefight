module Integrations
  module MapEventSources
    # Northflank's changes, sent to a webhook notification integration Firefight adds with the connection's API token,
    # restricted to the connected projects (@northflank/js-client, CreateNotificationData, POST /v1/integrations/notifications,
    # whose projects is a list, so one integration covers every project the connection reaches).
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
      # A container evicted, one near its memory or CPU for a while, and a volume filling up are what a watch on a crash or
      # a disk waits for, so they wake it too.
      SERVICE_EVENTS = %w[
        service:deployment:status-update service:autoscaling:event build:start build:success build:failure build:abort
        infrastructure:service:container-crash infrastructure:service:container-eviction infrastructure:service:container-memorySpike90
        infrastructure:service:container-memorySustained90 infrastructure:service:container-cpuSpike90 infrastructure:service:container-cpuSustained90
        infrastructure:build:container-eviction infrastructure:build:container-memorySpike90 infrastructure:build:container-memorySustained90
        infrastructure:build:container-cpuSpike90 infrastructure:build:container-cpuSustained90
      ].freeze
      ADDON_EVENTS = %w[
        addon-backup:start addon-backup:success addon-backup:failure addon-backup:abort infrastructure:addon:container-crash
        infrastructure:addon:container-eviction infrastructure:addon:container-cpuSpike90 infrastructure:addon:container-cpuSustained90
        infrastructure:addon-volume:usage-75-exceeded infrastructure:addon-volume:usage-90-exceeded infrastructure:addon-volume:disk-autoresize-triggered
      ].freeze
      JOB_EVENTS = %w[
        job-run:start job-run:success job-run:failure job-run:abort job-run:terminate infrastructure:job:container-crash
        infrastructure:job:container-eviction infrastructure:job:container-memorySpike90 infrastructure:job:container-memorySustained90
        infrastructure:job:container-cpuSpike90 infrastructure:job:container-cpuSustained90
      ].freeze
      # A release flow's run and a template's run as they go. Northflank has no event for a workflow's run, so a watch on
      # one reads it each minute. template-run may come for a workflow too, which Northflank does not say, so it re-reads
      # the project's workflows.
      RELEASE_FLOW_EVENTS = %w[
        release-flow-template-run:start release-flow-template-run:update release-flow-template-run:success
        release-flow-template-run:failure release-flow-template-run:aborted
      ].freeze
      TEMPLATE_EVENTS = %w[template-run:queued template-run:start template-run:update template-run:success template-run:failure].freeze
      EVENTS = (SERVICE_EVENTS + ADDON_EVENTS + JOB_EVENTS + RELEASE_FLOW_EVENTS + TEMPLATE_EVENTS).freeze
      KINDS = { "service" => nil, "addon" => ResourceMap::KIND_DATABASE, "job" => ResourceMap::KIND_JOB }.freeze
      WEBHOOK_NAME = "Firefight live updates".freeze

      PERMISSION_NOTE = "Firefight follows a Northflank project through a webhook notification integration, which the API token's role " \
                        "can add only with Notifications Read, Create and Delete (Account, Observability)".freeze

      class << self
        def verify(raw_body:, headers:, secret:)
          secret.present? && ActiveSupport::SecurityUtils.secure_compare(headers[TOKEN_HEADER].to_s, secret)
        end

        # One event about the service, addon or job the data names. A service's id may be a build service's, so its kind
        # is left for the re-read to say. A release names the pipeline its flow belongs to, and the stage where the data
        # says it, or else every release flow is read again, since Northflank does not document what that data holds.
        def events(payload, headers:)
          type = payload["event"].to_s.delete_prefix(TRIGGER)
          return [] unless EVENTS.include?(type)

          data = payload["data"].is_a?(Hash) ? payload["data"] : {}
          scope = release_scope(type, data) || resource_scope(data)
          return [] unless scope

          [ ResourceMap::Event.new(id: headers[EVENT_ID_HEADER].presence, at: Time.current, action: ResourceMap::Event::UPDATED, scope: scope) ]
        end

        # Whether the integration registered from before sends every event Firefight now follows, so one made before a new
        # event joined is registered again with it. One Northflank no longer has is registered again too.
        def register_again?(row, url:)
          return false if row.map_events_webhook_id.blank?

          sent = api(row).notification(row.map_events_webhook_id)["events"].to_h.select { |_event, on| on }.keys
          (EVENTS.map { |event| "#{TRIGGER}#{event}" } - sent).any?
        rescue NorthflankApi::NotFound
          true
        end

        # Adds one integration restricted to every project the connection reaches, deleting first one Firefight added
        # before at this connection's own address, whose secret Northflank never shows again. An integration at any other
        # address is never touched. Northflank does not say whether an unrestricted integration covers a project made
        # later, so a connection that reaches every project names each, and is registered again when they change
        # (MapEvents.register_again?).
        def register(row, url:)
          api = api(row)
          api.notifications.items.select { |integration| integration["webhook"] == url }.each { |integration| api.delete_notification(integration["id"]) }
          secret = SecureRandom.hex(32)
          projects = projects_of(row)
          created = api.create_notification(name: "#{WEBHOOK_NAME} #{projects.first(3).join(' ')} #{row.map_events_token.to_s.first(6)}".squish, url: url,
                                            secret: secret, events: EVENTS.map { |event| "#{TRIGGER}#{event}" }, projects: projects)
          MapEventSource::Webhook.new(id: created["id"], secret: secret, scopes: projects)
        rescue NorthflankApi::Refused => error
          raise MapEventSource::Refused, Sentence.all(error, PERMISSION_NOTE)
        end

        # An integration already gone from Northflank is taken back all the same.
        def remove(row, webhook_id)
          api(row).delete_notification(webhook_id)
        rescue NorthflankApi::NotFound
          nil
        end

        def limits = "Northflank says when a service deploys or builds, a database backs up, a job runs and a release flow runs. A " \
                     "workflow's run sends nothing, so a watch on one reads it each minute. A service, database, job, workflow or pipeline " \
                     "added or removed, and a change to its settings, reach the map at each hourly sweep."

        private

        def release_scope(type, data)
          if RELEASE_FLOW_EVENTS.include?(type)
            pipeline = data.dig("pipeline", "id").presence || data["pipelineId"].presence
            stage = [ data["stage"], data.dig("releaseFlow", "stage"), data.dig("pipeline", "stage") ].find { |each| each.is_a?(String) && each.present? }
            return ResourceMap::Scope.new(kind: ResourceMap::KIND_RELEASE_FLOW, external_id: "#{pipeline}/#{stage.downcase}") if pipeline && stage
            return ResourceMap::Scope.new(kind: ResourceMap::KIND_PIPELINE, external_id: pipeline) if pipeline

            ResourceMap::Scope.new(kind: ResourceMap::KIND_RELEASE_FLOW)
          elsif TEMPLATE_EVENTS.include?(type)
            ResourceMap::Scope.new(kind: ResourceMap::KIND_WORKFLOW)
          end
        end

        def resource_scope(data)
          about, kind = KINDS.filter_map { |key, each| [ data.dig(key, "id"), each ] if data.dig(key, "id").present? }.first
          about && ResourceMap::Scope.new(kind: kind, external_id: about)
        end

        def api(row)
          token = ConnectionSettings.of(row).credential(Packs::Northflank::API_TOKEN)
          raise Integrations::Error, "This connection has no Northflank token. Reconnect it on the Integrations page." if token.blank?

          NorthflankApi.new(token)
        end

        def projects_of(row)
          ConnectionSettings.of(row).scopes.presence || raise(Integrations::Error, "This connection reaches no Northflank project. Choose one on the Integrations page.")
        end
      end
    end
  end
end
