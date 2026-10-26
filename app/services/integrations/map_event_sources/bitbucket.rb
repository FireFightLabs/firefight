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
      # A build status created or updated on a commit, which is how Bitbucket Pipelines and any other CI report a run
      # starting and ending (Event payloads, Build status created and Build status updated). A workspace webhook offers
      # no event for a pipeline or a deployment of its own, only pipeline:span_created, one per span of its traces. They
      # change nothing on the map and have a watch check now.
      COMMIT_STATUS_CREATED = "repo:commit_status_created".freeze
      COMMIT_STATUS_UPDATED = "repo:commit_status_updated".freeze
      RUN_EVENTS = [ COMMIT_STATUS_CREATED, COMMIT_STATUS_UPDATED ].freeze
      # The states a build's status ends in, as a run that ended reads them. INPROGRESS has not ended.
      STATUS_ENDS = { "SUCCESSFUL" => RunsEnded::OUTCOME_SUCCEEDED, "FAILED" => RunsEnded::OUTCOME_FAILED, "STOPPED" => RunsEnded::OUTCOME_CANCELLED }.freeze
      PROVIDER_NAME = "Bitbucket".freeze
      # A pull request opened, changed (its reviewers, its title or new commits on its branch), merged or declined, and a
      # comment on it, so Halon reviews one when it is asked, when it opens or when it gets new commits, answers a reply in
      # its own threads and learns it merged (Event payloads, Pull request events). Bitbucket does not say what an update
      # changed, so each update names the head it has and whether Firefight is among its reviewers, and the app tells a
      # new head from one it already reviewed.
      PULL_REQUEST_CREATED = "pullrequest:created".freeze
      PULL_REQUEST_UPDATED = "pullrequest:updated".freeze
      PULL_REQUEST_FULFILLED = "pullrequest:fulfilled".freeze
      PULL_REQUEST_REJECTED = "pullrequest:rejected".freeze
      PULL_REQUEST_COMMENTED = "pullrequest:comment_created".freeze
      REVIEW_EVENTS = [ PULL_REQUEST_CREATED, PULL_REQUEST_UPDATED, PULL_REQUEST_FULFILLED, PULL_REQUEST_REJECTED, PULL_REQUEST_COMMENTED ].freeze
      PERSON = "user".freeze
      # The workspace events Firefight follows, from those Bitbucket lists for a workspace webhook (GET
      # /hook_events/workspace). repo:created and repo:imported are listed there and in the OpenAPI description, and have
      # no payload of their own on the Event payloads page, so only their repository's full_name is read.
      EVENTS = [ PUSH, CREATED, IMPORTED, DELETED, TRANSFER, UPDATED, *RUN_EVENTS, *REVIEW_EVENTS ].freeze
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

        # Registers a webhook in each workspace the connection reaches, every one with the same secret, or takes back one
        # Firefight registered before at this connection's own address, giving it the new secret, since Bitbucket never
        # shows one again. A workspace the connection no longer reaches loses the webhook Firefight registered there. A
        # webhook at any other address is never touched. The id is each workspace's webhook, by workspace.
        def register(row, url:)
          api = api(row)
          settings = ConnectionSettings.of(row)
          workspaces = workspaces_of(row)
          secret = SecureRandom.hex(32)
          registrations(row.map_events_webhook_id, settings).except(*workspaces).each { |workspace, hook| forget(api, workspace, hook) }
          body = { "description" => WEBHOOK_NAME, "url" => url, "active" => true, "secret" => secret, "events" => EVENTS }
          made = workspaces.to_h do |workspace|
            hooks = "/workspaces/#{Http.segment(workspace)}/hooks"
            own = api.list(hooks).first.find { |hook| hook["url"] == url }
            hook = own ? api.put("#{hooks}/#{Http.segment(own['uuid'])}", body) : api.post(hooks, body)
            [ workspace, hook["uuid"] ]
          end
          MapEventSource::Webhook.new(id: made.to_json, secret: secret, scopes: workspaces)
        rescue BitbucketApi::Refused, BitbucketApi::NotFound => error
          raise MapEventSource::Refused, Sentence.all(error, OWNER_NOTE)
        end

        def wakes?(payload, headers:) = RUN_EVENTS.include?(headers[EVENT_HEADER].to_s)

        # A build's status on a commit that ended, as a CI run (Integrations::RunsEnded). Bitbucket gives the status no
        # id of its own, so the build's key, the commit and how it ended name it.
        def runs_ended(payload, headers:)
          return [] unless RUN_EVENTS.include?(headers[EVENT_HEADER].to_s)

          status = payload["commit_status"].to_h
          outcome = STATUS_ENDS[status["state"].to_s]
          repository = payload.dig("repository", "full_name").presence || status.dig("repository", "full_name")
          commit = status.dig("commit", "hash")
          return [] unless outcome && repository.present? && status["key"].present?

          [ RunsEnded::Run.new(kind: RunsEnded::KIND_CI, outcome: outcome, provider: PROVIDER_NAME, reference: [ repository, status["key"], commit, status["state"] ].join(":"),
                               name: status["name"].presence || status["key"], place: repository, ref: status["refname"], commit: commit, url: status["url"]) ]
        end

        # What a delivery says about a pull request Halon may review (Integrations::PullRequestReviews). An update names
        # its head as pushed, and as asked of whoever is among its reviewers, once a head.
        def review_signals(payload, headers:)
          repository = payload.dig("repository", "full_name").to_s
          pull = payload["pullrequest"].to_h
          return [] unless repository.include?("/") && pull["id"].present?

          event = headers[EVENT_HEADER].to_s
          return comment_signals(payload, repository, pull) if event == PULL_REQUEST_COMMENTED

          head = pull.dig("source", "commit", "hash")
          base = { repository: repository, number: pull["id"].to_i, head_sha: head, author: payload.dig("actor", "account_id"),
                   person: payload.dig("actor", "type").to_s == PERSON, draft: pull["draft"] == true }
          reviewers = Array(pull["reviewers"]).select { |person| person.is_a?(Hash) }.map { |person| [ person["account_id"], person["uuid"], person["nickname"] ].compact }
          asked = [ PullRequestReviews::Signal.new(kind: PullRequestReviews::REQUESTED, reference: "#{repository}##{pull['id']}:asked:#{head}", reviewers: reviewers.flatten, **base) ]
          case event
          when PULL_REQUEST_CREATED
            [ PullRequestReviews::Signal.new(kind: PullRequestReviews::OPENED, reference: "#{repository}##{pull['id']}:open", **base), *(asked if reviewers.any?) ]
          when PULL_REQUEST_UPDATED
            [ PullRequestReviews::Signal.new(kind: PullRequestReviews::PUSHED, reference: "#{repository}##{pull['id']}:push:#{head}", **base), *(asked if reviewers.any?) ]
          when PULL_REQUEST_FULFILLED then [ PullRequestReviews::Signal.new(kind: PullRequestReviews::MERGED, reference: "#{repository}##{pull['id']}:merge", **base) ]
          when PULL_REQUEST_REJECTED then [ PullRequestReviews::Signal.new(kind: PullRequestReviews::CLOSED, reference: "#{repository}##{pull['id']}:close", **base) ]
          else []
          end
        end

        # Whether a workspace's webhook misses an event Firefight now follows, such as one registered before runs were
        # followed, or is gone from Bitbucket.
        def register_again?(row, **)
          api = api(row)
          registrations(row.map_events_webhook_id, ConnectionSettings.of(row)).any? do |workspace, hook|
            (EVENTS - Array(api.get("/workspaces/#{Http.segment(workspace)}/hooks/#{Http.segment(hook)}")["events"])).any?
          rescue BitbucketApi::NotFound
            true
          end
        end

        # Every workspace's webhook. One already gone from Bitbucket is taken back all the same.
        def remove(row, webhook_id)
          api = api(row)
          registrations(webhook_id, ConnectionSettings.of(row)).each { |workspace, hook| forget(api, workspace, hook) }
        end

        # The branches a push moved, for the handbook pages synced from them (Integrations::RepositoryDocuments).
        def branch_pushes(payload, headers:)
          name = payload.dig("repository", "full_name").to_s
          return [] unless headers[EVENT_HEADER].to_s == PUSH && name.include?("/")

          Array(payload.dig("push", "changes")).filter_map { |change| change.dig("new", "name") if change.dig("new", "type") == BRANCH }.uniq
                                               .map { |branch| RepositoryDocuments::Push.new(repository: name, branch: branch) }
        end

        private

        # A comment on a pull request. A reply names the comment it answers as parent, which is the thread it is in.
        def comment_signals(payload, repository, pull)
          comment = payload["comment"].to_h
          return [] if comment["id"].blank?

          [ PullRequestReviews::Signal.new(kind: PullRequestReviews::COMMENTED, repository: repository, number: pull["id"].to_i,
                                           reference: "#{repository}##{pull['id']}:comment:#{comment['id']}", head_sha: pull.dig("source", "commit", "hash"),
                                           author: payload.dig("actor", "account_id"), person: payload.dig("actor", "type").to_s == PERSON,
                                           comment: comment["id"].to_s, thread: comment.dig("parent", "id")&.to_s, body: comment.dig("content", "raw").to_s) ]
        end

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

        def workspaces_of(row)
          ConnectionSettings.of(row).scopes.presence || raise(Integrations::Error, "This connection reaches no Bitbucket workspace. Choose one on the Integrations page.")
        end

        def forget(api, workspace, hook)
          api.delete("/workspaces/#{Http.segment(workspace)}/hooks/#{Http.segment(hook)}")
        rescue BitbucketApi::NotFound
          nil
        end
      end
    end
  end
end
