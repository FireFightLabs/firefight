module Integrations
  module MapEventSources
    # PlanetScale's changes, sent to a webhook on each database. Firefight adds that webhook itself through PlanetScale's
    # API (Create a webhook) when the connection's credentials reach it, a sign-in or a service token with its id
    # (Packs::Planetscale.reaches_api?), and otherwise an admin adds it by hand. Each database's webhook has a secret
    # PlanetScale makes for it, which the API answers with and its page shows under Show secret, and signs every delivery
    # with an HMAC-SHA256 hex digest of the body in X-PlanetScale-Signature (planetscale.com/docs/api/webhooks, Validating a
    # webhook signature), so the connection keeps every database's secret. The body names the organization, the database
    # and the branch or deploy request it is about (planetscale.com/docs/api/webhook-events, Webhook request body
    # parameters), which the map reads again. A deploy request's event also wakes the watches reading through the
    # connection, and one that applied or errored is a deploy that ended.
    class Planetscale < MapEventSource
      SIGNATURE_HEADER = "X-PlanetScale-Signature".freeze
      PROVIDER = MapReaders::Planetscale::PROVIDER
      PROVIDER_NAME = MapReaders::Planetscale::NAME

      # The events that change what the map shows of a branch, its state and whether it is production, from the event
      # reference (planetscale.com/docs/api/webhook-events, Webhook events). A deploy request changes its target branch's
      # schema, and closing one may delete its own branch (resource.branch_deleted).
      BRANCH_READY = "branch.ready".freeze
      BRANCH_EVENTS = [ BRANCH_READY, "branch.sleeping", "branch.start_maintenance", "branch.primary_promoted" ].freeze
      DEPLOY_REQUEST_CLOSED = "deploy_request.closed".freeze
      SCHEMA_APPLIED = "deploy_request.schema_applied".freeze
      ERRORED = "deploy_request.errored".freeze
      DEPLOY_REQUEST_EVENTS = [
        "deploy_request.opened", "deploy_request.queued", "deploy_request.in_progress", "deploy_request.pending_cutover",
        SCHEMA_APPLIED, ERRORED, "deploy_request.reverted", DEPLOY_REQUEST_CLOSED
      ].freeze
      EVENTS = (BRANCH_EVENTS + DEPLOY_REQUEST_EVENTS).freeze
      # A deploy request that finished applying its schema, or stopped on an error, is a deploy that ended.
      DEPLOY_ENDS = { SCHEMA_APPLIED => RunsEnded::OUTCOME_SUCCEEDED, ERRORED => RunsEnded::OUTCOME_FAILED }.freeze
      # Stands for every webhook Firefight added, one a database.
      ALL_DATABASES = "all-databases".freeze
      WEBHOOKS_A_DATABASE = 5

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
          [ ResourceMap::Event.new(id: "planetscale-#{Digest::SHA256.hexdigest(payload.to_json)}", at: happened_at(payload),
                                   action: type == BRANCH_READY ? ResourceMap::Event::ADDED : ResourceMap::Event::UPDATED, scope: scope) ]
        end

        # A deploy request moving has the watches reading through the connection check it now.
        def wakes?(payload, headers:) = DEPLOY_REQUEST_EVENTS.include?(payload["event"].to_s) && payload["database"].present?

        # A deploy request that applied its schema or errored, as a deploy that ended (Integrations::RunsEnded), named by its
        # number into the branch it deploys to.
        def runs_ended(payload, headers:)
          outcome = DEPLOY_ENDS[payload["event"].to_s]
          request = payload["resource"].is_a?(Hash) ? payload["resource"] : {}
          database = payload["database"].presence
          return [] unless outcome && database && request["number"].present?

          [ RunsEnded::Run.new(kind: RunsEnded::KIND_DEPLOY, outcome: outcome, provider: PROVIDER_NAME,
                               reference: "deploy_request:#{payload['organization']}/#{database}/#{request['number']}:#{outcome}",
                               name: "deploy request ##{request['number']}", place: [ database, request["into_branch"] ].compact_blank.join("/"),
                               ref: request["branch"], url: request["html_url"], environment: request["into_branch"]) ]
        end

        def limits = "PlanetScale says when a branch or a deploy request changes in a database with Firefight's webhook. A database " \
                     "added since is given one at the next hourly sweep, and resizes and settings changes reach the map at each sweep."

        # Every database's webhook signs with its own secret, so each one is kept.
        def many_secrets? = true

        # Firefight adds the webhooks itself only when the connection's credentials reach PlanetScale's API.
        def registers_for?(row) = Packs::Planetscale.reaches_api?(row)

        # Adds Firefight's webhook to every database the map holds for the connection, or takes back one at the connection's
        # own address from before, with the events Firefight follows. A webhook at any other address is never touched.
        # Each database's secret is kept, one a line. A database PlanetScale refuses one for, such as one with all its five
        # webhooks taken, is left to the next sweep, and only when every one is refused is the registration refused.
        def register(row, url:)
          api = Packs::Planetscale.api(row)
          refused = []
          secrets = databases(row).filter_map do |organization, database|
            own = own_webhooks(api, organization, database, url)
            hook = own.first
            hook = if hook.nil? then api.create_webhook(organization, database, url: url, events: EVENTS)
            elsif !covers?(hook) then api.update_webhook(organization, database, hook["id"], events: EVENTS).then { |updated| updated.merge("secret" => updated["secret"].presence || hook["secret"]) }
            else hook
            end
            hook["secret"].presence
          rescue PlanetscaleApi::Refused => error
            refused << Sentence.join("#{organization}/#{database}", error.message)
            nil
          end
          raise MapEventSource::Refused, Sentence.all("PlanetScale would not add Firefight's webhook", refused.join(" ")) if secrets.empty? && refused.any?

          # A refused database may still have a webhook from before, signing with a secret saved then, which is kept.
          secrets.concat(row.map_events_secrets) if refused.any?
          MapEventSource::Webhook.new(id: ALL_DATABASES, secret: secrets.uniq.join("\n").presence)
        end

        # PlanetScale allows five webhooks a database (planetscale.com/docs/api/webhooks), so a database whose others hold
        # four would give Firefight its last, which a person decides. Firefight's own from before costs nothing.
        def confirmation_for(row, url:)
          api = Packs::Planetscale.api(row)
          crowded = databases(row).select do |organization, database|
            hooks = api.webhooks(organization, database)
            hooks.none? { |hook| hook["url"] == url } && hooks.size >= WEBHOOKS_A_DATABASE - 1
          end
          return if crowded.empty?

          names = crowded.map { |organization, database| "#{organization}/#{database}" }.to_sentence
          "Firefight's webhook would take the last of the #{WEBHOOKS_A_DATABASE} webhooks PlanetScale allows on #{names}, so it adds them once you turn live updates on."
        end

        # Whether a database on the map has no webhook of Firefight's that follows every event, such as one added since.
        def register_again?(row, url:)
          api = Packs::Planetscale.api(row)
          databases(row).any? { |organization, database| own_webhooks(api, organization, database, url).none? { |hook| covers?(hook) } }
        end

        # Takes back every webhook Firefight added, on whichever databases they are.
        def remove(row, _webhook_id)
          url = MapEvents.url_for(row) || raise(Integrations::Error, "Firefight's own address is not set, so its webhooks on PlanetScale cannot be told apart.")
          api = Packs::Planetscale.api(row)
          databases(row).each do |organization, database|
            own_webhooks(api, organization, database, url).each do |hook|
              api.delete_webhook(organization, database, hook["id"])
            rescue PlanetscaleApi::NotFound
              nil
            end
          end
        end

        def setup_steps
          [
            "In PlanetScale, open a database Firefight should follow, then Settings, then Webhooks, and choose Add webhook.",
            "Paste the address above as the URL.",
            "Select these events: #{EVENTS.join(', ')}. PlanetScale sends deploy request events for Vitess databases only.",
            "Save the webhook, choose Show secret from its menu, and add that secret below.",
            "Do the same for each database. PlanetScale allows #{WEBHOOKS_A_DATABASE} webhooks a database, and Firefight's uses one of them."
          ]
        end

        def by_hand_note
          "A connection made by signing in to PlanetScale, or with a service token and its id, has Firefight add these webhooks itself."
        end

        private

        # A deploy request that closed and deleted its branch is about that branch, which the re-read finds gone. Any
        # other is about the branch it deploys into.
        def branch_of(type, resource)
          return resource["branch"] if type == DEPLOY_REQUEST_CLOSED && resource["branch_deleted"]

          resource["into_branch"]
        end

        def happened_at(payload) = payload["timestamp"].is_a?(Numeric) ? Time.zone.at(payload["timestamp"]) : Time.current

        # Every database the map holds for the connection, by its organization and name.
        def databases(row)
          ResourceMap::Resource.present.where(integration_environment: row, provider: PROVIDER, kind: ResourceMap::KIND_DATABASE)
                               .order(:account, :external_id).pluck(:account, :external_id).uniq
        end

        def own_webhooks(api, organization, database, url) = api.webhooks(organization, database).select { |hook| hook["url"] == url }

        def covers?(hook) = hook["enabled"] != false && (EVENTS - Array(hook["events"])).empty?
      end
    end
  end
end
