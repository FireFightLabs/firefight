module Integrations
  module MapEventSources
    # CircleCI's outbound webhooks, one Firefight adds to each project the connection's token reaches (v2 createWebhook,
    # whose only scope is a project), for workflow-completed and job-completed, the two events CircleCI sends
    # (guides/integration/outbound-webhooks.adoc). Each delivery is signed in circleci-signature as v1=<hex HMAC-SHA256 of
    # the body> keyed by the webhook's signing secret, the only version so far, and names its event in circleci-event-type
    # and itself by its id (reference/outbound-webhooks-reference.adoc). A run ending changes nothing the map shows, so a
    # delivery only wakes the watches reading through the connection and says a CI run ended.
    class Circleci < MapEventSource
      SIGNATURE_HEADER = "circleci-signature".freeze
      EVENT_HEADER = "circleci-event-type".freeze
      SIGNATURE_VERSION = "v1".freeze
      WORKFLOW_COMPLETED = "workflow-completed".freeze
      JOB_COMPLETED = "job-completed".freeze
      EVENTS = [ WORKFLOW_COMPLETED, JOB_COMPLETED ].freeze
      WEBHOOK_NAME = "Firefight live updates".freeze
      PROVIDER_NAME = "CircleCI".freeze
      # Stands for every webhook Firefight added, one per project.
      ALL_PROJECTS = "all-projects".freeze
      # How a workflow ended (outbound-webhooks.adoc, workflow-completed's statuses).
      ENDS = { "success" => RunsEnded::OUTCOME_SUCCEEDED, "failed" => RunsEnded::OUTCOME_FAILED, "error" => RunsEnded::OUTCOME_FAILED,
               "unauthorized" => RunsEnded::OUTCOME_FAILED, "canceled" => RunsEnded::OUTCOME_CANCELLED }.freeze
      MCP_ONLY = "Live updates need a CircleCI connection made with a personal API token, since CircleCI's MCP server cannot add webhooks".freeze
      TOO_MANY = "CircleCI listed more projects than Firefight reads at once in the organization".freeze
      NEEDS = "Adding a webhook to a project needs the token's user to manage the project's settings".freeze

      class << self
        # Only the latest signature version is checked, as CircleCI asks, so a delivery cannot be passed off with an older one.
        def verify(raw_body:, headers:, secret:)
          return false if secret.blank?

          signatures = headers[SIGNATURE_HEADER].to_s.split(",").to_h { |pair| pair.strip.split("=", 2) }
          given = signatures[SIGNATURE_VERSION].to_s
          given.present? && ActiveSupport::SecurityUtils.secure_compare(given, OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body))
        end

        def events(_payload, headers:) = []

        def wakes?(payload, headers:) = EVENTS.include?(headers[EVENT_HEADER].to_s) && payload.dig("project", "id").present?

        # A workflow that ended, as a CI run (Integrations::RunsEnded), with its project, branch, commit and page. A retry of
        # a workflow is a workflow of its own, so each is one run.
        def runs_ended(payload, headers:)
          return [] unless headers[EVENT_HEADER].to_s == WORKFLOW_COMPLETED

          workflow = payload["workflow"].to_h
          outcome = ENDS[workflow["status"].to_s]
          return [] unless outcome && workflow["id"].present?

          git = payload.dig("pipeline", "trigger_parameters", "git").to_h
          vcs = payload.dig("pipeline", "vcs").to_h
          [ RunsEnded::Run.new(kind: RunsEnded::KIND_CI, outcome: outcome, provider: PROVIDER_NAME, reference: "workflow:#{workflow['id']}:#{outcome}",
                               name: workflow["name"], place: payload.dig("project", "slug").presence || payload.dig("project", "name"),
                               ref: vcs["branch"].presence || vcs["tag"].presence || git["branch"].presence || git["tag"].presence,
                               commit: vcs["revision"].presence || git["checkout_sha"].presence, url: workflow["url"]) ]
        end

        # Adds a webhook for both events to every project, or puts one Firefight added before at this connection's own
        # address back as it should be, enabled and with the connection's secret, since CircleCI never shows a secret again.
        # The secret is kept before the first is added, so a project's deliveries are accepted while the rest are added. A
        # webhook at any other address is never touched.
        def register(row, url:)
          api = api(row)
          secret = secret_of(row)
          projects(api).each do |project|
            own = own_webhooks(api, project, url).first
            if own then api.update_webhook(own["id"], url: url, secret: secret, events: EVENTS)
            else api.create_webhook(project["id"], name: WEBHOOK_NAME, url: url, secret: secret, events: EVENTS)
            end
          end
          MapEventSource::Webhook.new(id: ALL_PROJECTS, secret: secret)
        rescue CircleciApi::Refused => error
          raise MapEventSource::Refused, Sentence.all(error, NEEDS)
        end

        # Whether a project has been added since, or CircleCI switched one of Firefight's webhooks off, either of which
        # registering again puts right.
        def register_again?(row, url:)
          api = api(row)
          projects(api).any? do |project|
            own = own_webhooks(api, project, url)
            own.none? { |hook| hook["is_enabled"] != false && (EVENTS - Array(hook["events"])).empty? }
          end
        end

        # Takes back every webhook Firefight added, whichever projects they are on. One already gone is taken back all the same.
        def remove(row, _webhook_id)
          url = MapEvents.url_for(row) || raise(Integrations::Error, "Firefight's own address is not set, so its webhooks on CircleCI cannot be told apart.")
          api = api(row)
          projects(api).each do |project|
            own_webhooks(api, project, url).each do |hook|
              api.delete_webhook(hook["id"])
            rescue CircleciApi::NotFound
              nil
            end
          end
        end

        def limits = "CircleCI says when a workflow or a job ends. A project added or removed reaches the map at each hourly sweep."

        private

        # Every project, or a refusal when an organization's list was cut short, so no webhook is added, checked or taken
        # back for only some of them while saying it was done.
        def projects(api)
          api.collaborations.flat_map do |organization|
            read = api.projects(organization["id"])
            raise Integrations::Error, "#{TOO_MANY} #{organization['name'] || organization['id']}." if read.incomplete?

            read.items
          end
        end

        def own_webhooks(api, project, url) = api.webhooks(project["id"]).select { |hook| hook["url"] == url }

        # The secret every webhook of the connection signs with, made once and kept on the row.
        def secret_of(row)
          return row.map_events_secret if row.map_events_secret.present?

          SecureRandom.hex(32).tap { |secret| row.save_map_events_secret!(secret) }
        end

        # A connection through CircleCI's hosted MCP server holds no API token, so it cannot add webhooks.
        def api(row)
          raise MapEventSource::Refused, "#{MCP_ONLY}." unless row.integration.native?

          token = ConnectionSettings.of(row).credential(Packs::Circleci::API_TOKEN)
          raise Integrations::Error, "This connection has no CircleCI token. Reconnect it on the Integrations page." if token.blank?

          CircleciApi.new(token)
        end
      end
    end
  end
end
