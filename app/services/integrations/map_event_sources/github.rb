module Integrations
  module MapEventSources
    # GitHub's changes, sent by Firefight's GitHub App for every installation to one address (docs.github.com, Using
    # webhooks with GitHub Apps), each delivery naming the installation it is about (installation.id). GitHub signs it
    # with an HMAC-SHA256 hex digest of the raw body keyed by the App's webhook secret, sent as sha256=<digest> in
    # X-Hub-Signature-256, and names it with a GUID in X-GitHub-Delivery and its event in X-GitHub-Event (docs.github.com,
    # Validating webhook deliveries, and Webhook events and payloads, Delivery headers). GitHub gives no time an event
    # happened, so each is recorded when it arrives.
    class Github < MapEventSource
      SIGNATURE_HEADER = "x-hub-signature-256".freeze
      SIGNATURE_PREFIX = "sha256=".freeze
      DELIVERY_HEADER = "x-github-delivery".freeze
      EVENT_HEADER = "x-github-event".freeze

      PUSH = "push".freeze
      REPOSITORY = "repository".freeze
      # Sent to every GitHub App without subscribing (docs.github.com, Webhook events and payloads, installation_repositories).
      INSTALLATION_REPOSITORIES = "installation_repositories".freeze
      # Also sent to every GitHub App, for the installation itself (Webhook events and payloads, installation): deleted,
      # suspend and unsuspend, new_permissions_accepted once an owner accepts permissions the App asked for, and created.
      INSTALLATION = "installation".freeze
      INSTALLATION_CHANGES = {
        "deleted" => Installations::CHANGE_REMOVED, "suspend" => Installations::CHANGE_SUSPENDED,
        "unsuspend" => Installations::CHANGE_RESTORED, "new_permissions_accepted" => Installations::CHANGE_ACCESS,
        "created" => Installations::CHANGE_ACCESS
      }.freeze

      # The repository event's actions that change what the map shows of a repository or which files it reads. Those
      # are its default branch (edited, changes.default_branch) and whether it is archived, which leaves its files
      # unread. A repository renamed or transferred is under another name now, which only a full read of the installation
      # finds. Made public or private changes nothing the map shows.
      ADDED = %w[created].freeze
      REMOVED = %w[deleted].freeze
      UPDATED = %w[archived unarchived].freeze
      EDITED = "edited".freeze
      MOVED = %w[renamed transferred].freeze
      # The push event's commits array holds at most 2048 commits (Webhook events and payloads, push), so a push with that
      # many may have changed files it does not list.
      MOST_COMMITS = 2048

      class << self
        def verify(raw_body:, headers:, secret:)
          signature = headers[SIGNATURE_HEADER].to_s
          return false if secret.blank? || !signature.start_with?(SIGNATURE_PREFIX)

          ActiveSupport::SecurityUtils.secure_compare(signature, SIGNATURE_PREFIX + OpenSSL::HMAC.hexdigest("SHA256", secret, raw_body))
        end

        def installation_of(payload, headers:) = payload.dig("installation", "id")

        # What a delivery says changed about the installation itself (Integrations::Installations), or nil. Repositories
        # added or removed may leave it none, which only reading what it lists says.
        def installation_change(payload, headers:)
          case headers[EVENT_HEADER].to_s
          when INSTALLATION then INSTALLATION_CHANGES[payload["action"].to_s]
          when INSTALLATION_REPOSITORIES then Installations::CHANGE_REACH
          end
        end

        def events(payload, headers:)
          delivery = headers[DELIVERY_HEADER].presence
          case headers[EVENT_HEADER].to_s
          when PUSH then push_events(payload, delivery)
          when REPOSITORY then repository_events(payload, delivery)
          when INSTALLATION_REPOSITORIES then reach_events(payload, delivery)
          else []
          end
        end

        private

        # A push to the default branch changes nothing the map shows of the repository itself, so it is read again only
        # when it may have changed an infrastructure file, or when the push does not list every file it changed.
        def push_events(payload, delivery)
          repository = payload["repository"].to_h
          return [] if payload["deleted"] || payload["ref"] != "refs/heads/#{repository['default_branch']}"
          return [] unless infrastructure_changed?(payload)

          [ event(delivery, ResourceMap::Event::UPDATED, repository["full_name"]) ].compact
        end

        # A push listing no commits moved the branch without new ones, such as a force push back to an older commit, so
        # it lists none of the files it changed either.
        def infrastructure_changed?(payload)
          commits = Array(payload["commits"])
          return true if commits.empty? || commits.size >= MOST_COMMITS

          commits.flat_map { |commit| Array(commit["added"]) + Array(commit["modified"]) + Array(commit["removed"]) }
                 .any? { |path| Packs::CodeHost::Infrastructure.defines?(path) }
        end

        def repository_events(payload, delivery)
          action = payload["action"].to_s
          name = payload.dig("repository", "full_name")
          return [ ResourceMap::Event.new(id: delivery, at: Time.current, action: ResourceMap::Event::RESCOPE) ] if MOVED.include?(action)

          change = change_of(action, payload)
          change ? [ event(delivery, change, name) ].compact : []
        end

        def change_of(action, payload)
          return ResourceMap::Event::ADDED if ADDED.include?(action)
          return ResourceMap::Event::REMOVED if REMOVED.include?(action)

          ResourceMap::Event::UPDATED if UPDATED.include?(action) || (action == EDITED && payload.dig("changes", "default_branch"))
        end

        # Repositories added to the installation are read one by one. One removed may still be public, which GitHub
        # answers for any token, so only a full read of what the installation lists says it is out of reach.
        def reach_events(payload, delivery)
          case payload["action"]
          when "added"
            Array(payload["repositories_added"]).filter_map { |repository| event(delivery, ResourceMap::Event::ADDED, repository["full_name"], each: true) }
          when "removed"
            [ ResourceMap::Event.new(id: delivery, at: Time.current, action: ResourceMap::Event::RESCOPE) ]
          else []
          end
        end

        # One delivery may name several repositories, each its own event, so the id names the repository too.
        def event(delivery, action, name, each: false)
          return if name.blank?

          ResourceMap::Event.new(id: delivery && (each ? "#{delivery}:#{name}" : delivery), at: Time.current, action: action,
                                 scope: ResourceMap::Scope.new(account: name.split("/").first, kind: ResourceMap::KIND_REPOSITORY, external_id: name))
        end
      end
    end
  end
end
