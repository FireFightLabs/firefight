module Integrations
  module MapEventSources
    # Azure DevOps' changes, sent to service hook subscriptions Firefight creates on each of the connection's projects
    # with its token (Subscriptions - Create, the Web Hooks consumer's httpRequest action, filtered to a project by the
    # projectId publisher input, as Create a service hook subscription programmatically writes it). Creating one needs
    # a project administrator. Azure DevOps does not sign a delivery, so Firefight sends its own secret as the Web Hooks
    # consumer's basic authentication password and compares it in constant time. The consumer's httpHeaders are shown to
    # anyone who can see the subscription (Service hook consumers, Web Hooks), while basicAuthPassword is a confidential
    # input Azure DevOps never shows again. A delivery names its event by eventType and itself by id, the same on every retry.
    class AzureDevops < MapEventSource
      BASIC_USER = "firefight".freeze
      BASIC = "Basic ".freeze
      # The events followed, each with the publisher and resource version its sample payload in Service hook events
      # gives. resourceVersion is left out where the page gives none, which Azure DevOps reads as its latest released one.
      GIT_PUSH = "git.push".freeze
      REPO_CREATED = "git.repo.created".freeze
      REPO_DELETED = "git.repo.deleted".freeze
      REPO_RENAMED = "git.repo.renamed".freeze
      BUILD_COMPLETE = "build.complete".freeze
      RUN_STATE = "ms.vss-pipelines.run-state-changed-event".freeze
      STAGE_STATE = "ms.vss-pipelines.stage-state-changed-event".freeze
      JOB_STATE = "ms.vss-pipelines.job-state-changed-event".freeze
      APPROVAL_PENDING = "ms.vss-pipelinechecks-events.approval-pending".freeze
      RELEASE_STARTED = "ms.azure-devops-release.deployment-started-event".freeze
      RELEASE_COMPLETED = "ms.azure-devops-release.deployment-completed-event".freeze
      EVENTS = {
        GIT_PUSH => [ "tfs", "1.0" ], REPO_CREATED => [ "tfs", "1.0-preview.1" ], REPO_DELETED => [ "tfs", "1.0-preview.1" ],
        REPO_RENAMED => [ "tfs", "1.0-preview.1" ], BUILD_COMPLETE => [ "tfs", "1.0" ], RUN_STATE => [ "pipelines", nil ],
        STAGE_STATE => [ "pipelines", "5.1-preview.1" ], JOB_STATE => [ "pipelines", "5.1-preview.1" ], APPROVAL_PENDING => [ "pipelines", nil ],
        RELEASE_STARTED => [ "rm", nil ], RELEASE_COMPLETED => [ "rm", nil ]
      }.freeze
      # About a run a watch may follow, which changes nothing on the map.
      RUN_EVENTS = [ BUILD_COMPLETE, RUN_STATE, STAGE_STATE, JOB_STATE, APPROVAL_PENDING, RELEASE_STARTED, RELEASE_COMPLETED ].freeze
      CONSUMER = "webHooks".freeze
      ACTION = "httpRequest".freeze
      # A subscription that still sends, as opposed to one a person or Azure DevOps switched off (SubscriptionStatus).
      SENDING = %w[enabled onProbation].freeze
      # A completed run's result, as a run that ended reads it (build.complete's resource, BuildResult).
      RUN_ENDS = { "succeeded" => RunsEnded::OUTCOME_SUCCEEDED, "partiallySucceeded" => RunsEnded::OUTCOME_SUCCEEDED,
                   "failed" => RunsEnded::OUTCOME_FAILED, "canceled" => RunsEnded::OUTCOME_CANCELLED }.freeze
      PROVIDER_NAME = "Azure DevOps".freeze
      ROLE_NOTE = "Azure DevOps lets a project administrator create service hook subscriptions, with a token that has Service Hooks " \
                  "(Read, query, & manage)".freeze

      class << self
        def verify(raw_body:, headers:, secret:)
          return false if secret.blank?

          given = headers["Authorization"].to_s
          return false unless given.start_with?(BASIC)

          ActiveSupport::SecurityUtils.secure_compare(Base64.strict_decode64(given.delete_prefix(BASIC)), "#{BASIC_USER}:#{secret}")
        rescue ArgumentError
          false
        end

        def events(payload, headers:)
          id = payload["id"].to_s.presence
          resource = payload["resource"].is_a?(Hash) ? payload["resource"] : {}
          case payload["eventType"].to_s
          when GIT_PUSH then push_events(id, resource)
          when REPO_CREATED then [ event(id, ResourceMap::Event::ADDED, resource.dig("repository", "project", "name"), resource.dig("repository", "name")) ].compact
          when REPO_DELETED then [ event(id, ResourceMap::Event::REMOVED, resource.dig("project", "name"), resource["repositoryName"]) ].compact
          when REPO_RENAMED
            # A rename moves the repository to another key, so only a read of every repository says which one it was.
            [ ResourceMap::Event.new(id: id, at: Time.current, action: ResourceMap::Event::RESCOPE, scope: ResourceMap::Scope.new(kind: ResourceMap::KIND_REPOSITORY)) ]
          else []
          end
        end

        def wakes?(payload, headers:) = RUN_EVENTS.include?(payload["eventType"].to_s)

        # A run that completed, as a CI run (Integrations::RunsEnded), from build.complete, which Azure DevOps sends once a
        # run of any pipeline ends.
        def runs_ended(payload, headers:)
          return [] unless payload["eventType"].to_s == BUILD_COMPLETE

          build = payload["resource"].to_h
          outcome = RUN_ENDS[build["result"].to_s]
          return [] unless outcome && build["id"].present?

          place = [ build.dig("project", "name"), build.dig("repository", "name") ].compact.join("/").presence || build.dig("definition", "name")
          [ RunsEnded::Run.new(kind: RunsEnded::KIND_CI, outcome: outcome, provider: PROVIDER_NAME, reference: "build:#{build['id']}:#{build['result']}",
                               name: build.dig("definition", "name").presence || "Run #{build['id']}", place: place,
                               ref: build["sourceBranch"].to_s.delete_prefix(Packs::AzureDevops::HEADS).presence, commit: build["sourceVersion"],
                               url: build.dig("_links", "web", "href")) ]
        end

        # The branches a push moved, for the handbook pages synced from them (Integrations::RepositoryDocuments).
        def branch_pushes(payload, headers:)
          return [] unless payload["eventType"].to_s == GIT_PUSH

          resource = payload["resource"].to_h
          name = repository_name(resource.dig("repository", "project", "name"), resource.dig("repository", "name"))
          return [] unless name

          Array(resource["refUpdates"]).filter_map do |update|
            ref = update["name"].to_s
            RepositoryDocuments::Push.new(repository: name, branch: ref.delete_prefix(Packs::AzureDevops::HEADS)) if ref.start_with?(Packs::AzureDevops::HEADS)
          end
        end

        # Subscribes to every event on each project the connection reaches, every subscription sending the same secret of
        # Firefight's own. Firefight's own from before at this connection's address is taken back first, since Azure DevOps
        # never shows a password again and a new secret is made each time. A project the
        # connection no longer reaches loses Firefight's subscriptions there. A subscription at any other address is never
        # touched. The id is each project's subscriptions, by project.
        def register(row, url:)
          api = api(row)
          settings = ConnectionSettings.of(row)
          projects = settings.scopes
          raise Integrations::Error, "This connection reaches no Azure DevOps project. Choose one on the Integrations page." if projects.empty?

          registrations(row.map_events_webhook_id, settings).except(*projects).each_value { |ids| forget(api, ids) }
          secret = SecureRandom.hex(32)
          made = projects.to_h do |project|
            project_id = api.get("/_apis/projects/#{Http.segment(project)}")["id"]
            ours(api, project_id, url).each { |subscription| forget(api, [ subscription["id"] ]) }
            [ project, EVENTS.map { |event_type, (publisher, version)| subscribe(api, project_id, event_type, publisher, version, url, secret)["id"] } ]
          end
          MapEventSource::Webhook.new(id: made.to_json, secret: secret, scopes: projects)
        rescue AzureDevopsApi::Refused => error
          raise MapEventSource::Refused, Sentence.all(error, ROLE_NOTE)
        end

        # Whether a subscription Firefight made is gone or no longer sends, such as one Azure DevOps disabled after failed
        # deliveries or one made before an event joined EVENTS.
        def register_again?(row, **)
          api = api(row)
          made = registrations(row.map_events_webhook_id, ConnectionSettings.of(row))
          return false if made.empty?

          made.values.any? do |ids|
            Array(ids).size < EVENTS.size || Array(ids).any? { |id| SENDING.exclude?(api.get("/_apis/hooks/subscriptions/#{Http.segment(id)}")["status"].to_s) }
          end
        rescue AzureDevopsApi::NotFound
          true
        end

        # Every project's subscriptions. One already gone from Azure DevOps is taken back all the same.
        def remove(row, webhook_id)
          api = api(row)
          registrations(webhook_id, ConnectionSettings.of(row)).each_value { |ids| forget(api, ids) }
        end

        def limits = "Azure DevOps says when a repository is pushed to, created, renamed or deleted, and when a run or release moves. " \
                     "A pipeline added, renamed or removed reaches the map at each hourly sweep."

        private

        def subscribe(api, project_id, event_type, publisher, version, url, secret)
          api.post("/_apis/hooks/subscriptions", {
            "publisherId" => publisher, "eventType" => event_type, "resourceVersion" => version, "consumerId" => CONSUMER, "consumerActionId" => ACTION,
            "publisherInputs" => { "projectId" => project_id }, "consumerInputs" => { "url" => url, "basicAuthUsername" => BASIC_USER, "basicAuthPassword" => secret }
          }.compact)
        end

        # Firefight's subscriptions from before on the project, by this connection's address (Subscriptions - List).
        def ours(api, project_id, url)
          api.values(api.get("/_apis/hooks/subscriptions", "consumerId" => CONSUMER, "consumerActionId" => ACTION)).select do |subscription|
            subscription.dig("consumerInputs", "url") == url && subscription.dig("publisherInputs", "projectId") == project_id
          end
        end

        def forget(api, ids)
          Array(ids).each do |id|
            api.delete("/_apis/hooks/subscriptions/#{Http.segment(id)}")
          rescue AzureDevopsApi::NotFound
            nil
          end
        end

        # A push to the default branch reads the repository again, since its payload lists commits but not the files they
        # changed, so any of them may be an infrastructure file.
        def push_events(id, resource)
          repository = resource["repository"].to_h
          default = repository["defaultBranch"].to_s
          moved = Array(resource["refUpdates"]).any? { |update| update["name"] == default }
          return [] unless moved

          [ event(id, ResourceMap::Event::UPDATED, repository.dig("project", "name"), repository["name"]) ].compact
        end

        def repository_name(project, name) = project.present? && name.present? ? "#{project}/#{name}" : nil

        def event(id, action, project, name)
          external_id = repository_name(project, name)
          return unless external_id

          ResourceMap::Event.new(id: id, at: Time.current, action: action, scope: ResourceMap::Scope.new(kind: ResourceMap::KIND_REPOSITORY, external_id: external_id))
        end

        def api(row)
          settings = ConnectionSettings.of(row)
          token = settings.credential(Packs::AzureDevops::TOKEN)
          raise Integrations::Error, "This connection has no Azure DevOps token. Reconnect it on the Integrations page." if token.blank?

          AzureDevopsApi.new(settings.field(Packs::AzureDevops::ORGANIZATION), token)
        end
      end
    end
  end
end
