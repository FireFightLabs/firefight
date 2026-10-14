module Integrations
  module MapEventSources
    # GitLab's changes, sent to a webhook Firefight registers with the connection's own token on GitLab.com or the
    # workspace's own GitLab. It is a group webhook when every project the connection reaches is in one group, which
    # covers the group's subgroups and also says when a project is created or deleted in it, or a project webhook when
    # it reaches one project (doc/api/group_webhooks.md and project_webhooks.md). GitLab sends the secret Firefight made as
    # X-Gitlab-Token and names the event in X-Gitlab-Event (doc/user/project/integrations/webhooks.md, Delivery headers).
    # GitLab gives no time a push happened, so each event is recorded when it arrives.
    class Gitlab < MapEventSource
      TOKEN_HEADER = "x-gitlab-token".freeze
      EVENT_HEADER = "x-gitlab-event".freeze
      # Each is the same for every retry of one delivery. GitLab sends webhook-id since 19.0 and Idempotency-Key since
      # 17.4, and before those the event's own X-Gitlab-Event-UUID (webhooks.md, Delivery headers).
      ID_HEADERS = %w[webhook-id idempotency-key x-gitlab-event-uuid].freeze
      PUSH_HOOK = "Push Hook".freeze
      # Sent to a group webhook only, when a project is created or deleted in the group (webhook_events.md, Project events).
      PROJECT_HOOK = "Project Hook".freeze
      PROJECT_CREATE = "project_create".freeze
      PROJECT_DESTROY = "project_destroy".freeze
      # About a run a watch may follow (webhook_events.md): a pipeline and a deployment at every change, and a job once
      # it ends or waits on a person. The webhook is registered for them, and one registered before them is registered
      # again.
      PIPELINE_HOOK = "Pipeline Hook".freeze
      JOB_HOOK = "Job Hook".freeze
      DEPLOYMENT_HOOK = "Deployment Hook".freeze
      JOB_ENDS = %w[success failed canceled skipped manual].freeze
      RUN_EVENTS = %w[pipeline_events job_events deployment_events].freeze
      # An issue at every change, so a label added to one starts a workflow (webhook_events.md, Work item events). A
      # confidential issue is sent only to a webhook that also asks for confidential issue events, which this one never
      # does, so none reaches Firefight.
      ISSUE_HOOK = "Issue Hook".freeze
      ISSUE_OPEN = "open".freeze
      ISSUE_EVENTS = %w[issues_events].freeze
      # What a webhook from before misses when it lacks any of these, so it is registered again.
      FOLLOWED_EVENTS = [ *RUN_EVENTS, *ISSUE_EVENTS ].freeze
      # The statuses a pipeline or a deployment ends on, as a run that ended reads them.
      RUN_ENDS = { "success" => RunsEnded::OUTCOME_SUCCEEDED, "failed" => RunsEnded::OUTCOME_FAILED, "canceled" => RunsEnded::OUTCOME_CANCELLED }.freeze
      PROVIDER_NAME = "GitLab".freeze
      # A push of more than 20 commits lists only the newest 20, and total_commits_count says how many there were
      # (webhook_events.md, Push events).
      MOST_COMMITS = 20
      WEBHOOK_NAME = "Firefight live updates".freeze
      # What Firefight keeps as the webhook's id is its own path in the API, so taking it back needs nothing else.
      HOOK_PATH = %r{\A/(groups|projects)/\d+/hooks/\d+\z}

      ROLE_NOTE = "Firefight follows a GitLab group through a group webhook, which needs GitLab Premium or Ultimate and the " \
                  "Owner role in the group, or one project through a project webhook, which needs the Maintainer role, and " \
                  "either needs a token with the api scope".freeze
      NO_PROJECTS = "This token reaches no GitLab projects, so there is nothing to follow".freeze
      MANY_GROUPS = "This token reaches projects outside one GitLab group, and one webhook follows one group or one project. " \
                    "Connect a group access token for each group to follow its projects as they change".freeze

      class << self
        def verify(raw_body:, headers:, secret:)
          return false if secret.blank?

          ActiveSupport::SecurityUtils.secure_compare(headers[TOKEN_HEADER].to_s, secret)
        end

        def events(payload, headers:)
          id = ID_HEADERS.lazy.filter_map { |header| headers[header].presence }.first
          case headers[EVENT_HEADER].to_s
          when PUSH_HOOK then push_events(payload, id)
          when PROJECT_HOOK then project_events(payload, id)
          else []
          end
        end

        # Registers the webhook for the group or project the connection reaches, or takes back one Firefight registered
        # before at this connection's own address there, giving it a new secret, since GitLab never shows one again. A
        # webhook at any other address is never touched.
        def register(row, url:)
          api = api(row)
          target, group = hook_target(api)
          secret = SecureRandom.hex(32)
          body = { "url" => url, "token" => secret, "name" => WEBHOOK_NAME, "push_events" => true, "enable_ssl_verification" => true,
                   **FOLLOWED_EVENTS.index_with(true) }
          body["project_events"] = true if group
          own = api.list("#{target}/hooks").first.find { |hook| hook["url"] == url }
          hook = own ? api.put("#{target}/hooks/#{own['id']}", body) : api.post("#{target}/hooks", body)
          MapEventSource::Webhook.new(id: "#{target}/hooks/#{hook['id']}", secret: secret)
        rescue GitlabApi::Refused, GitlabApi::NotFound => error
          raise MapEventSource::Refused, Sentence.all(error, ROLE_NOTE)
        end

        # Whether the webhook Firefight registered misses an event about runs or issues, such as one registered before they
        # were followed. One gone from GitLab is registered again too.
        def register_again?(row, **)
          webhook_id = row.map_events_webhook_id.to_s
          return false unless webhook_id.match?(HOOK_PATH)

          hook = api(row).get(webhook_id)
          FOLLOWED_EVENTS.any? { |event| hook[event] != true }
        rescue GitlabApi::NotFound
          true
        end

        def wakes?(payload, headers:)
          case headers[EVENT_HEADER].to_s
          when PIPELINE_HOOK, DEPLOYMENT_HOOK then true
          when JOB_HOOK then JOB_ENDS.include?(payload["build_status"].to_s)
          else false
          end
        end

        # A pipeline that ended, as a CI run, and a deployment that ended, as a deploy (Integrations::RunsEnded). GitLab
        # sends a pipeline and a deployment at every change, so only the statuses it ends on are kept (webhook_events.md,
        # Pipeline events and Deployment events).
        def runs_ended(payload, headers:)
          project = payload.dig("project", "path_with_namespace")
          return [] if project.blank?

          case headers[EVENT_HEADER].to_s
          when PIPELINE_HOOK then pipeline_ended(payload, project)
          when DEPLOYMENT_HOOK then deployment_ended(payload, project)
          else []
          end
        end

        # Labels added to an issue (Integrations::IssueLabels), which are those it was opened with, or those an update's
        # changes.labels holds now and did not before. user is who did it, and GitLab may send its email hidden.
        def labelled(payload, headers:)
          return [] unless headers[EVENT_HEADER].to_s == ISSUE_HOOK

          issue = payload["object_attributes"].to_h
          project = payload.dig("project", "path_with_namespace")
          return [] if issue["id"].blank? || project.blank?

          added = labels_added(payload, issue["action"].to_s == ISSUE_OPEN)
          return [] if added.empty?

          email = payload.dig("user", "email").to_s
          [ IssueLabels::Labelled.new(
            reference: "#{issue['id']}:#{added.map { |label| label['id'] }.sort.join(',')}:#{issue['updated_at']}", labels: added.map { |label| label["title"] },
            issue_key: "#{project}##{issue['iid']}", issue_title: issue["title"].presence, issue_url: issue["url"].presence, text: issue["description"].presence,
            asker_name: payload.dig("user", "name").presence, asker_email: (email if email.match?(URI::MailTo::EMAIL_REGEXP))
          ) ]
        end

        # A webhook already gone from GitLab is taken back all the same.
        def remove(row, webhook_id)
          raise Integrations::Error, "Firefight's GitLab webhook is not one it registered." unless webhook_id.to_s.match?(HOOK_PATH)

          api(row).delete(webhook_id)
        rescue GitlabApi::NotFound
          nil
        end

        # The branch a push moved, for the handbook pages synced from it (Integrations::RepositoryDocuments).
        def branch_pushes(payload, headers:)
          return [] unless headers[EVENT_HEADER].to_s == PUSH_HOOK

          name = payload.dig("project", "path_with_namespace")
          ref = payload["ref"].to_s
          name.present? && ref.start_with?("refs/heads/") ? [ RepositoryDocuments::Push.new(repository: name, branch: ref.delete_prefix("refs/heads/")) ] : []
        end

        private

        def labels_added(payload, opened)
          named = ->(labels) { Array(labels).select { |label| label.is_a?(Hash) && label["title"].present? } }
          return named.(payload["labels"]) if opened

          change = payload.dig("changes", "labels").to_h
          before = named.(change["previous"]).map { |label| label["id"] }
          named.(change["current"]).reject { |label| before.include?(label["id"]) }
        end

        def pipeline_ended(payload, project)
          pipeline = payload["object_attributes"].to_h
          outcome = RUN_ENDS[pipeline["status"].to_s]
          return [] unless outcome && pipeline["id"].present?

          [ RunsEnded::Run.new(kind: RunsEnded::KIND_CI, outcome: outcome, provider: PROVIDER_NAME, reference: "pipeline:#{pipeline['id']}:#{pipeline['status']}",
                               name: pipeline["name"].presence || "Pipeline #{pipeline['id']}", place: project, ref: pipeline["ref"], commit: pipeline["sha"],
                               url: pipeline["url"]) ]
        end

        def deployment_ended(payload, project)
          outcome = RUN_ENDS[payload["status"].to_s]
          return [] unless outcome && payload["deployment_id"].present?

          [ RunsEnded::Run.new(kind: RunsEnded::KIND_DEPLOY, outcome: outcome, provider: PROVIDER_NAME,
                               reference: "deployment:#{payload['deployment_id']}:#{payload['status']}", name: payload["environment"], place: project,
                               ref: payload["ref"], commit: payload["commit_sha"].presence || payload["short_sha"], url: payload["deployable_url"],
                               environment: payload["environment"]) ]
        end

        def push_events(payload, id)
          project = payload["project"].to_h
          return [] unless payload["ref"] == "refs/heads/#{project['default_branch']}" && infrastructure_changed?(payload)

          [ event(id, ResourceMap::Event::UPDATED, project["path_with_namespace"]) ].compact
        end

        # A push to the default branch changes nothing the map shows of the project itself, so it is read again only when
        # it may have changed an infrastructure file, or when it does not list every file it changed.
        def infrastructure_changed?(payload)
          commits = Array(payload["commits"])
          return true if commits.empty? || payload["total_commits_count"].to_i > commits.size

          commits.flat_map { |commit| Array(commit["added"]) + Array(commit["modified"]) + Array(commit["removed"]) }
                 .any? { |path| Packs::CodeHost::Infrastructure.defines?(path) }
        end

        def project_events(payload, id)
          action = { PROJECT_CREATE => ResourceMap::Event::ADDED, PROJECT_DESTROY => ResourceMap::Event::REMOVED }[payload["event_name"]]
          action ? [ event(id, action, payload["path_with_namespace"]) ].compact : []
        end

        def event(id, action, path)
          return if path.blank? || !path.include?("/")

          ResourceMap::Event.new(id: id, at: Time.current, action: action,
                                 scope: ResourceMap::Scope.new(account: path.rpartition("/").first, kind: ResourceMap::KIND_REPOSITORY, external_id: path))
        end

        # The projects the connection reaches, as the sweep lists them, and the one group they all sit in. Answers the
        # API path the webhook goes under, and whether it is a group's.
        def hook_target(api)
          projects, = api.list("/projects", { "membership" => true, "order_by" => "id", "sort" => "asc" }, pages: Packs::Gitlab::MAX_PROJECT_PAGES)
          raise MapEventSource::Refused, NO_PROJECTS if projects.empty?
          return [ "/projects/#{Integer(projects.sole['id'])}", false ] if projects.one?

          group = common_group(projects)
          raise MapEventSource::Refused, MANY_GROUPS unless group

          [ "/groups/#{Integer(api.get("/groups/#{Http.segment(group)}", "with_projects" => false)['id'])}", true ]
        end

        # The deepest group every project is in, or nil when one is in a person's own namespace or they share none.
        def common_group(projects)
          namespaces = projects.map { |project| project["namespace"].to_h }
          return if namespaces.any? { |namespace| namespace["kind"] != "group" || namespace["full_path"].blank? }

          paths = namespaces.map { |namespace| namespace["full_path"].split("/") }
          shared = paths.first.each_with_index.take_while { |segment, index| paths.all? { |path| path[index] == segment } }.map(&:first)
          shared.join("/").presence
        end

        def api(row)
          settings = ConnectionSettings.of(row)
          token = settings.credential(Packs::Gitlab::TOKEN)
          raise Integrations::Error, "This connection has no GitLab token. Reconnect it on the Integrations page." if token.blank?

          GitlabApi.new(settings.field(Packs::Gitlab::URL), token)
        end
      end
    end
  end
end
