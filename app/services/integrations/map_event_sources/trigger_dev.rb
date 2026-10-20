module Integrations
  module MapEventSources
    # Trigger.dev's alerts, sent to a webhook an admin adds on the project's Alerts page, since Trigger.dev's API offers no
    # way to add one (docs/troubleshooting-alerts.mdx, How to setup alerts). Each webhook alert has a secret Trigger.dev
    # shows when it is made, and every delivery is signed with an HMAC-SHA256 hex digest of the body in
    # x-trigger-signature-hmacsha256, as its SDK checks it (packages/trigger-sdk/src/v3/webhooks.ts). A deployment that
    # succeeded changes which tasks the environment runs, so the connection is read again. A run, deployment or error
    # group that failed changes nothing on the map, and wakes a watch on the environment at once.
    class TriggerDev < MapEventSource
      SIGNATURE_HEADER = "x-trigger-signature-hmacsha256".freeze
      PROVIDER = Packs::TriggerDev::PROVIDER

      # The alert types, from the docs' Common properties.
      RUN_FAILED = "alert.run.failed".freeze
      DEPLOYMENT_SUCCEEDED = "alert.deployment.success".freeze
      DEPLOYMENT_FAILED = "alert.deployment.failed".freeze
      ERROR_GROUP = "alert.error".freeze
      EVENTS = [ RUN_FAILED, DEPLOYMENT_SUCCEEDED, DEPLOYMENT_FAILED, ERROR_GROUP ].freeze
      DEPLOY_ENDS = { DEPLOYMENT_SUCCEEDED => RunsEnded::OUTCOME_SUCCEEDED, DEPLOYMENT_FAILED => RunsEnded::OUTCOME_FAILED }.freeze

      class << self
        def verify(raw_body:, headers:, secret:)
          return false if secret.blank?

          ActiveSupport::SecurityUtils.secure_compare(headers[SIGNATURE_HEADER].to_s, OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, raw_body))
        end

        # A deployment that succeeded reads the connection again, by the delivery's own id, the same for every retry.
        def events(payload, headers:)
          return [] unless payload["type"] == DEPLOYMENT_SUCCEEDED && payload["id"].present?

          [ ResourceMap::Event.new(id: payload["id"].to_s, at: happened_at(payload["created"]), action: ResourceMap::Event::RESCOPE) ]
        end

        def wakes?(payload, headers:) = EVENTS.include?(payload["type"].to_s)

        # A deployment that succeeded or failed, as a deploy that ended (Integrations::RunsEnded), in the environment it
        # deployed to.
        def runs_ended(payload, headers:)
          outcome = DEPLOY_ENDS[payload["type"].to_s]
          object = payload["object"].is_a?(Hash) ? payload["object"] : {}
          deployment = object["deployment"].to_h
          return [] unless outcome && deployment["id"].present?

          [ RunsEnded::Run.new(kind: RunsEnded::KIND_DEPLOY, outcome: outcome, provider: PROVIDER, reference: "deploy:#{deployment['id']}:#{outcome}",
                               name: deployment["version"], place: object.dig("project", "ref").presence || object.dig("project", "name"),
                               ref: object.dig("git", "branch"), commit: object.dig("git", "commitSha"), environment: object.dig("environment", "slug")) ]
        end

        def limits = "Trigger.dev says when a deployment succeeds or fails, a run fails and an error group alerts, for the alerts set up to " \
                     "send to Firefight. Anything else reaches the map at each hourly sweep."

        # Every webhook alert has a secret of its own, so each one an admin saves is kept.
        def many_secrets? = true

        def setup_steps
          [
            "In Trigger.dev, open the project and environment this connection reads, then Alerts, and choose New alert.",
            "Choose Webhook, and paste the address above as its URL.",
            "Select Run fails, Deployment fails and Deployment succeeds, then save the alert.",
            "Copy the secret Trigger.dev shows for the webhook and add it below.",
            "To hear of error groups too, open Errors, choose Configure alerts, add a webhook with the same address, and add its secret below."
          ]
        end

        private

        def happened_at(created)
          Time.iso8601(created.to_s)
        rescue ArgumentError
          Time.current
        end
      end
    end
  end
end
