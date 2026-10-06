module Integrations
  module MapEventSources
    # PlanetScale's changes, sent to a webhook an admin adds to each database, since Firefight reaches PlanetScale through
    # its MCP server and so cannot add one itself. Each database's webhook has a secret PlanetScale makes for it, shown
    # under the webhook's Show secret, and signs every delivery with an HMAC-SHA256 hex digest of the body in
    # X-PlanetScale-Signature (planetscale.com/docs/api/webhooks, Validating a webhook signature), so the connection keeps
    # every database's secret. The body names the organization, the database and the branch or deploy request it is about
    # (planetscale.com/docs/api/webhook-events, Webhook request body parameters), which the map reads again.
    class Planetscale < MapEventSource
      SIGNATURE_HEADER = "X-PlanetScale-Signature".freeze

      # The events that change what the map shows of a branch, its state and whether it is production, from the event
      # reference (planetscale.com/docs/api/webhook-events, Webhook events). A deploy request changes its target branch's
      # schema, and closing one may delete its own branch (resource.branch_deleted).
      BRANCH_READY = "branch.ready".freeze
      BRANCH_EVENTS = [ BRANCH_READY, "branch.sleeping", "branch.start_maintenance", "branch.primary_promoted" ].freeze
      DEPLOY_REQUEST_CLOSED = "deploy_request.closed".freeze
      DEPLOY_REQUEST_EVENTS = [
        "deploy_request.opened", "deploy_request.queued", "deploy_request.in_progress", "deploy_request.pending_cutover",
        "deploy_request.schema_applied", "deploy_request.errored", "deploy_request.reverted", DEPLOY_REQUEST_CLOSED
      ].freeze
      EVENTS = (BRANCH_EVENTS + DEPLOY_REQUEST_EVENTS).freeze

      class << self
        def verify(raw_body:, headers:, secret:)
          return false if secret.blank?

          ActiveSupport::SecurityUtils.secure_compare(headers[SIGNATURE_HEADER].to_s, OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, raw_body))
        end

        # One event about the branch it names, read again with its database. PlanetScale's body has no id of its own,
        # and a redelivery sends the same body, so a digest of the body makes it a no-op.
        def events(payload, headers:)
          type = payload["event"].to_s
          organization = payload["organization"].presence
          database = payload["database"].presence
          resource = payload["resource"].is_a?(Hash) ? payload["resource"] : {}
          return [] unless EVENTS.include?(type) && organization && database

          branch = BRANCH_EVENTS.include?(type) ? resource["name"] : branch_of(type, resource)
          return [] if branch.blank?

          scope = ResourceMap::Scope.new(account: organization, kind: ResourceMap::KIND_BRANCH, external_id: "#{database}/#{branch}")
          at = payload["timestamp"].is_a?(Numeric) ? Time.zone.at(payload["timestamp"]) : Time.current
          [ ResourceMap::Event.new(id: "planetscale-#{Digest::SHA256.hexdigest(payload.to_json)}", at: at,
                                   action: type == BRANCH_READY ? ResourceMap::Event::ADDED : ResourceMap::Event::UPDATED, scope: scope) ]
        end

        def limits = "PlanetScale says when a branch changes in a database whose webhook is set up. A database removed, or one without " \
                     "Firefight's webhook, reaches the map at each hourly sweep."

        # Every database's webhook signs with its own secret, so each one an admin saves is kept.
        def many_secrets? = true

        def setup_steps
          [
            "In PlanetScale, open a database Firefight should follow, then Settings, then Webhooks, and choose Add webhook.",
            "Paste the address above as the URL.",
            "Select these events: #{EVENTS.join(', ')}. PlanetScale sends deploy request events for Vitess databases only.",
            "Save the webhook, choose Show secret from its menu, and add that secret below.",
            "Do the same for each database. PlanetScale allows five webhooks a database, and Firefight's uses one of them."
          ]
        end

        private

        # A deploy request that closed and deleted its branch is about that branch, which the re-read finds gone. Any
        # other is about the branch it deploys into.
        def branch_of(type, resource)
          return resource["branch"] if type == DEPLOY_REQUEST_CLOSED && resource["branch_deleted"]

          resource["into_branch"]
        end
      end
    end
  end
end
