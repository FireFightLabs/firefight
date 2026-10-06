module Integrations
  module MapEventSources
    # Bitbucket's changes, sent to a workspace webhook Firefight registers with the connection's own token, which fires
    # for events from every repository in the workspace and which only a workspace owner can add (Bitbucket's OpenAPI
    # description, POST /workspaces/{workspace}/hooks, api.bitbucket.org/swagger.json). Bitbucket signs each delivery with
    # an HMAC-SHA256 hex digest of the raw body keyed by the webhook's secret, sent as sha256=<digest> in X-Hub-Signature,
    # names the event in X-Event-Key and the request in X-Request-UUID (support.atlassian.com, Manage webhooks, Secure
    # webhooks, and Event payloads, HTTP headers). Bitbucket gives no time an event happened, so each is recorded when it
    # arrives.
    class Bitbucket < MapEventSource
      SIGNATURE_HEADER = "x-hub-signature".freeze
      SIGNATURE_PREFIX = "sha256=".freeze
      EVENT_HEADER = "x-event-key".freeze
      REQUEST_HEADER = "x-request-uuid".freeze

      PUSH = "repo:push".freeze
      CREATED = "repo:created".freeze
      IMPORTED = "repo:imported".freeze
      # Sent once a repository is hard deleted, which can be up to 30 days after it was (Event payloads, Deleted), so the
      # daily read usually finds it gone first.
      DELETED = "repo:deleted".freeze
      TRANSFER = "repo:transfer".freeze
      UPDATED = "repo:updated".freeze
      # The workspace events the map reads, from those Bitbucket lists for a workspace webhook (GET
      # /hook_events/workspace). repo:created and repo:imported are listed there and in the OpenAPI description, and have
      # no payload of their own on the Event payloads page, so only their repository's full_name is read.
      EVENTS = [ PUSH, CREATED, IMPORTED, DELETED, TRANSFER, UPDATED ].freeze
      BRANCH = "branch".freeze
      WEBHOOK_NAME = "Firefight live updates".freeze

      OWNER_NOTE = "Firefight follows a Bitbucket workspace through a workspace webhook, which only a workspace owner's token " \
                   "can add, with the read:webhook:bitbucket, write:webhook:bitbucket and delete:webhook:bitbucket scopes".freeze

      class << self
        def verify(raw_body:, headers:, secret:)
          signature = headers[SIGNATURE_HEADER].to_s
          return false if secret.blank? || !signature.start_with?(SIGNATURE_PREFIX)

          ActiveSupport::SecurityUtils.secure_compare(signature, SIGNATURE_PREFIX + OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body))
        end

        def events(payload, headers:)
          id = headers[REQUEST_HEADER].presence
          name = payload.dig("repository", "full_name").to_s
          return [] unless name.include?("/")

          case headers[EVENT_HEADER].to_s
          when PUSH then push_events(payload, id, name)
          when CREATED, IMPORTED then [ repository_event(id, ResourceMap::Event::ADDED, name) ]
          when DELETED then [ repository_event(id, ResourceMap::Event::REMOVED, name) ]
          # A repository under another name, or moved between workspaces, is found only by reading the workspace again.
          when TRANSFER then [ ResourceMap::Event.new(id: id, at: Time.current, action: ResourceMap::Event::RESCOPE) ]
          when UPDATED then payload.dig("changes", "full_name") ? [ ResourceMap::Event.new(id: id, at: Time.current, action: ResourceMap::Event::RESCOPE) ] : []
          else []
          end
        end

        # Registers the workspace's webhook, or takes back one Firefight registered before at this connection's own
        # address, giving it a new secret, since Bitbucket never shows one again. A webhook at any other address is never
        # touched.
        def register(row, url:)
          api = api(row)
          hooks = "/workspaces/#{Http.segment(workspace_of(row))}/hooks"
          secret = SecureRandom.hex(32)
          body = { "description" => WEBHOOK_NAME, "url" => url, "active" => true, "secret" => secret, "events" => EVENTS }
          own = api.list(hooks).first.find { |hook| hook["url"] == url }
          hook = own ? api.put("#{hooks}/#{Http.segment(own['uuid'])}", body) : api.post(hooks, body)
          MapEventSource::Webhook.new(id: hook["uuid"], secret: secret)
        rescue BitbucketApi::Refused, BitbucketApi::NotFound => error
          raise MapEventSource::Refused, Sentence.all(error, OWNER_NOTE)
        end

        # A webhook already gone from Bitbucket is taken back all the same.
        def remove(row, webhook_id)
          api(row).delete("/workspaces/#{Http.segment(workspace_of(row))}/hooks/#{Http.segment(webhook_id)}")
        rescue BitbucketApi::NotFound
          nil
        end

        private

        # A push does not say which branch is the repository's main one, so each branch it moved is read as a branch,
        # and the pack reads the repository again only for the main one. Its payload names no changed files, so a push to
        # the main branch reads the repository's infrastructure files again (Event payloads, Push).
        def push_events(payload, id, name)
          branches = Array(payload.dig("push", "changes")).filter_map { |change| change.dig("new", "name") if change.dig("new", "type") == BRANCH }.uniq
          branches.map do |branch|
            ResourceMap::Event.new(id: id && "#{id}:#{branch}", at: Time.current, action: ResourceMap::Event::UPDATED,
                                   scope: ResourceMap::Scope.new(account: name.split("/").first, kind: ResourceMap::KIND_BRANCH, external_id: "#{name}/#{branch}"))
          end
        end

        def repository_event(id, action, name)
          ResourceMap::Event.new(id: id, at: Time.current, action: action,
                                 scope: ResourceMap::Scope.new(account: name.split("/").first, kind: ResourceMap::KIND_REPOSITORY, external_id: name))
        end

        def api(row)
          token = ConnectionSettings.of(row).credential(Packs::Bitbucket::TOKEN)
          raise Integrations::Error, "This connection has no Bitbucket token. Reconnect it on the Integrations page." if token.blank?

          BitbucketApi.new(token)
        end

        def workspace_of(row)
          ConnectionSettings.of(row).field(Packs::Bitbucket::WORKSPACE) || raise(Integrations::Error, "This connection has no Bitbucket workspace. Reconnect it.")
        end
      end
    end
  end
end
