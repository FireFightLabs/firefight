module Integrations
  module MapEventSources
    # Netlify's deploy notifications, sent to outgoing webhooks Firefight adds to each site the connection's token reaches
    # (createHookBySiteId, a url hook for one event of one site, netlify/open-api swagger.yml and Netlify's own MCP server,
    # netlify/netlify-mcp events/hooks-api.ts). Netlify has no hook for a whole team, so there is one hook per site and
    # event. It signs each delivery with a JWS in X-Webhook-Signature, an HS256 token keyed by the hook's secret whose iss is
    # netlify and whose sha256 is the hex SHA-256 of the body (docs.netlify.com, Deploy notifications, Payload signature),
    # and names the event in X-Netlify-Event. The body is the deploy, which names its site. Outgoing webhooks are on every
    # plan (Deploy notifications, HTTP POST request).
    class Netlify < MapEventSource
      SIGNATURE_HEADER = "x-webhook-signature".freeze
      EVENT_HEADER = "x-netlify-event".freeze
      ISSUER = "netlify".freeze
      ALGORITHM = "HS256".freeze

      # A deploy publishing (deploy_created fires when a deploy succeeds, netlify/netlify-mcp events/registry.ts) and an
      # earlier one published again change the deploy, commit and branch the map shows for a site. Nothing else Netlify
      # sends does, and it sends nothing when a site is added, removed or its settings change.
      PUBLISHED = "deploy_created".freeze
      RESTORED = "deploy_restored".freeze
      EVENTS = [ PUBLISHED, RESTORED ].freeze
      # A deploy preview or branch deploy is not what the site serves.
      PRODUCTION = "production".freeze
      # Stands for every hook Firefight added, which are one per site and event.
      ALL_SITES = "all-sites".freeze

      REFUSED = "Netlify does not send deploy notifications to an outgoing webhook on this team's plan".freeze

      class << self
        def verify(raw_body:, headers:, secret:)
          return false if secret.blank?

          claims, = JWT.decode(headers[SIGNATURE_HEADER].to_s, secret, true, algorithm: ALGORITHM, iss: ISSUER, verify_iss: true)
          claims["sha256"].is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(claims["sha256"], Digest::SHA256.hexdigest(raw_body))
        rescue JWT::DecodeError
          false
        end

        # One event about the site a production deploy belongs to. A retry of a delivery is the same deploy at the same
        # update, so its id is too.
        def events(payload, headers:)
          type = headers[EVENT_HEADER].to_s
          site = payload["site_id"].presence
          return [] unless site && EVENTS.include?(type)
          return [] unless [ nil, "", PRODUCTION ].include?(payload["context"])

          at = payload["published_at"].presence || payload["updated_at"]
          [ ResourceMap::Event.new(id: [ type, payload["id"], payload["updated_at"] ].join(":"), at: time(at), action: ResourceMap::Event::UPDATED,
                                   scope: ResourceMap::Scope.new(kind: ResourceMap::KIND_SITE, external_id: site)) ]
        end

        # Adds a hook for each event to every site, or takes back one Firefight added before at this connection's own
        # address, turning it on again if Netlify disabled it. Every site's hooks share the connection's secret, which is
        # kept before the first is added, so a site's deliveries are accepted while the rest are still being added. A hook at
        # any other address is never touched.
        def register(row, url:)
          api = api(row)
          secret = secret_of(row)
          sites = api.sites.items
          offered = offered_by_team(api, sites)
          raise MapEventSource::Refused, "#{REFUSED}." if sites.any? && offered.values.all?(&:empty?)

          sites.each do |site|
            own = own_hooks(api, site, url)
            offered.fetch(site["account_id"]).each do |event|
              hook = own.find { |each| each["event"] == event }
              if hook.nil? then api.create_hook(site["id"], event: event, url: url, secret: secret)
              elsif hook["disabled"] then api.enable_hook(hook["id"])
              end
            end
          end
          MapEventSource::Webhook.new(id: ALL_SITES, secret: secret)
        rescue NetlifyApi::Refused => error
          raise MapEventSource::Refused, Sentence.all(error, REFUSED)
        end

        # Whether a site has been added since, or Netlify disabled one of Firefight's hooks, either of which registering
        # again puts right.
        def register_again?(row, url:)
          api = api(row)
          sites = api.sites.items
          offered = offered_by_team(api, sites)
          sites.any? do |site|
            own = own_hooks(api, site, url)
            offered.fetch(site["account_id"]).any? { |event| own.none? { |hook| hook["event"] == event && !hook["disabled"] } }
          end
        end

        # Takes back every hook Firefight added, whichever sites they are on. One already gone is taken back all the same.
        def remove(row, _webhook_id)
          url = MapEvents.url_for(row) || raise(Integrations::Error, "Firefight's own address is not set, so its hooks on Netlify cannot be told apart.")
          api = api(row)
          api.sites.items.each do |site|
            own_hooks(api, site, url).each do |hook|
              api.delete_hook(hook["id"])
            rescue NetlifyApi::NotFound
              nil
            end
          end
        end

        def limits = "Netlify says when a site publishes a deploy. A site added or removed, and a change to its settings, reach the map at each hourly sweep."

        private

        # The events each team's plan lets a hook fire for, asked of one of its sites, since the plan is the team's.
        def offered_by_team(api, sites)
          sites.group_by { |site| site["account_id"] }.transform_values do |team_sites|
            type = api.hook_types(team_sites.first["id"]).find { |each| each["name"] == NetlifyApi::URL_HOOK } || {}
            EVENTS & (Array(type["events"]) - Array(type["restricted_events"]))
          end
        end

        def own_hooks(api, site, url)
          api.hooks(site["id"]).select { |hook| hook["type"] == NetlifyApi::URL_HOOK && hook.dig("data", "url") == url }
        end

        # The secret every hook of the connection signs with, made once and kept on the row.
        def secret_of(row)
          return row.map_events_secret if row.map_events_secret.present?

          SecureRandom.hex(32).tap { |secret| row.save_map_events_secret!(secret) }
        end

        def time(value)
          Time.iso8601(value.to_s)
        rescue ArgumentError
          Time.current
        end

        def api(row)
          token = ConnectionSettings.of(row).credential(Packs::Netlify::API_TOKEN)
          raise Integrations::Error, "This connection has no Netlify token. Reconnect it on the Integrations page." if token.blank?

          NetlifyApi.new(token)
        end
      end
    end
  end
end
