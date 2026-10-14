require "test_helper"

module Integrations
  module MapEventSources
    class GitlabTest < ActiveSupport::TestCase
      URL = "https://firefight.example.com/api/v1/map_events/token-1".freeze
      PROJECTS_QUERY = { "membership" => true, "order_by" => "id", "sort" => "asc" }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "gitlab", name: "GitLab")
        @row = @integration.integration_environments.create!
        Packs::Gitlab.store_credentials!(@row, Packs::Gitlab::TOKEN => "glpat-token")
        GitlabApi.any_instance.expects(:delete).never
      end

      test "a delivery carrying the secret Firefight made is GitLab's, and one without it is not" do
        assert Gitlab.verify(raw_body: "{}", headers: { "x-gitlab-token" => "made-secret" }, secret: "made-secret")
        assert_not Gitlab.verify(raw_body: "{}", headers: { "x-gitlab-token" => "guessed" }, secret: "made-secret")
        assert_not Gitlab.verify(raw_body: "{}", headers: {}, secret: "made-secret")
        assert_not Gitlab.verify(raw_body: "{}", headers: { "x-gitlab-token" => "" }, secret: nil)
      end

      test "a push to the default branch that changes an infrastructure file re-reads its project, and any other push nothing" do
        event = push_events({ "modified" => [ "deploy/k8s/web.yaml" ] }).sole
        assert_equal [ "retry-safe-id", ResourceMap::Event::UPDATED ], [ event.id, event.action ]
        assert_equal ResourceMap::Scope.new(account: "acme/platform", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/platform/web"), event.scope

        assert_empty push_events({ "modified" => [ "app/controller/application.rb" ], "added" => [ "CHANGELOG" ] })
        assert_empty push_events({ "added" => [ "main.tf" ] }, ref: "refs/heads/feature")
        assert_equal 1, push_events({ "modified" => [ "README.md" ] }, total: 25).size, "a push of more than 20 commits lists only the newest 20"
        assert_equal "event-uuid", Gitlab.events(push([ { "added" => [ "main.tf" ] } ]), headers: { "x-gitlab-event" => "Push Hook", "x-gitlab-event-uuid" => "event-uuid" }).sole.id,
                     "an instance older than 17.4 names an event by its uuid alone"
      end

      test "a project created or deleted in the group is read again, and other events are not" do
        created = project_event("project_create").sole
        assert_equal [ ResourceMap::Event::ADDED, "acme/platform/new" ], [ created.action, created.scope.external_id ]
        assert_equal ResourceMap::Event::REMOVED, project_event("project_destroy").sole.action
        assert_empty project_event("project_rename")
        assert_empty Gitlab.events({ "object_kind" => "merge_request" }, headers: { "x-gitlab-event" => "Merge Request Hook" })
      end

      test "projects in one group get a group webhook there, for pushes and its projects, beside one at another address left alone" do
        projects([ project(1, "acme/platform/web", "acme/platform"), project(2, "acme/platform/infra/dns", "acme/platform/infra") ])
        GitlabApi.any_instance.stubs(:get).with("/groups/acme%2Fplatform", { "with_projects" => false }).returns("id" => 7)
        GitlabApi.any_instance.stubs(:list).with("/groups/7/hooks").returns([ [ { "id" => 3, "url" => "https://example.com/theirs" } ], false ])
        GitlabApi.any_instance.expects(:put).never
        GitlabApi.any_instance.expects(:post).with("/groups/7/hooks", has_entries("url" => URL, "push_events" => true, "project_events" => true, "enable_ssl_verification" => true,
                                                                                    "pipeline_events" => true, "job_events" => true, "deployment_events" => true,
                                                                                    "issues_events" => true))
                 .returns("id" => 11, "group_id" => 7)

        webhook = Gitlab.register(@row, url: URL)

        assert_equal "/groups/7/hooks/11", webhook.id
        assert_match(/\A\h{64}\z/, webhook.secret)
      end

      test "a connection reaching one project gets a project webhook, and Firefight's from before at this address gets a new secret" do
        projects([ project(5, "someone/web", "someone", kind: "user") ])
        GitlabApi.any_instance.stubs(:list).with("/projects/5/hooks").returns([ [ { "id" => 3, "url" => "https://example.com/theirs" }, { "id" => 9, "url" => URL } ], false ])
        GitlabApi.any_instance.expects(:post).never
        GitlabApi.any_instance.expects(:put).with("/projects/5/hooks/9", Not(has_key("project_events"))).returns("id" => 9, "project_id" => 5)

        assert_equal "/projects/5/hooks/9", Gitlab.register(@row, url: URL).id
      end

      test "a token without the role or tier for a webhook, or reaching projects in more than one group, is told why" do
        projects([ project(1, "acme/web", "acme"), project(2, "other/api", "other") ])
        assert_equal Gitlab::MANY_GROUPS, assert_raises(MapEventSource::Refused) { Gitlab.register(@row, url: URL) }.message

        projects([ project(1, "acme/web", "acme"), project(2, "me/notes", "me", kind: "user") ])
        assert_raises(MapEventSource::Refused) { Gitlab.register(@row, url: URL) }

        projects([])
        assert_equal Gitlab::NO_PROJECTS, assert_raises(MapEventSource::Refused) { Gitlab.register(@row, url: URL) }.message

        projects([ project(1, "acme/web", "acme"), project(2, "acme/api", "acme") ])
        GitlabApi.any_instance.stubs(:get).with("/groups/acme", { "with_projects" => false }).returns("id" => 7)
        GitlabApi.any_instance.stubs(:list).with("/groups/7/hooks").raises(GitlabApi::Refused, "GitLab answered 403: 403 Forbidden")
        refusal = assert_raises(MapEventSource::Refused) { Gitlab.register(@row, url: URL) }
        assert_equal "GitLab answered 403: 403 Forbidden. #{Gitlab::ROLE_NOTE}.", refusal.message
      end

      test "a self-managed GitLab is registered with at its own address" do
        @row.store_fields!(Packs::Gitlab::URL => "https://gitlab.example.com")
        gitlab = mock("gitlab")
        gitlab.stubs(:list).with("/projects", PROJECTS_QUERY, pages: Packs::Gitlab::MAX_PROJECT_PAGES).returns([ [ project(5, "acme/web", "acme") ], false ])
        gitlab.stubs(:list).with("/projects/5/hooks").returns([ [], false ])
        gitlab.expects(:post).with("/projects/5/hooks", has_entry("url" => URL)).returns("id" => 1)
        GitlabApi.expects(:new).with("https://gitlab.example.com", "glpat-token").returns(gitlab)

        assert_equal "/projects/5/hooks/1", Gitlab.register(@row.reload, url: URL).id
      end

      test "removing takes back Firefight's webhook by its own path, one GitLab no longer has is done, and any other path is refused" do
        GitlabApi.any_instance.unstub(:delete)
        GitlabApi.any_instance.expects(:delete).with("/groups/7/hooks/11").returns(nil)
        Gitlab.remove(@row, "/groups/7/hooks/11")

        GitlabApi.any_instance.stubs(:delete).raises(GitlabApi::NotFound, "GitLab answered 404: 404 Not found")
        assert_nil Gitlab.remove(@row, "/projects/5/hooks/9")
        assert_raises(Integrations::Error) { Gitlab.remove(@row, "/projects/5") }
      end

      test "a pipeline or deployment at any change and a job once it ended wake watches, and change nothing on the map" do
        headers = ->(event) { { "x-gitlab-event" => event, "idempotency-key" => "id-1" } }
        pipeline = { "object_kind" => "pipeline", "object_attributes" => { "id" => 31, "status" => "running" }, "project" => { "path_with_namespace" => "acme/platform/web" } }
        assert Gitlab.wakes?(pipeline, headers: headers.("Pipeline Hook"))
        assert_empty Gitlab.events(pipeline, headers: headers.("Pipeline Hook"))
        assert Gitlab.wakes?({ "object_kind" => "deployment", "status" => "success" }, headers: headers.("Deployment Hook"))
        assert Gitlab.wakes?({ "object_kind" => "build", "build_status" => "failed" }, headers: headers.("Job Hook"))
        assert_not Gitlab.wakes?({ "object_kind" => "build", "build_status" => "running" }, headers: headers.("Job Hook"))
        assert_not Gitlab.wakes?(push([]), headers: headers.("Push Hook"))
      end

      test "a webhook registered before runs or issues were followed is registered again, and one that follows them is left" do
        @row.update!(map_events_webhook_id: "/groups/7/hooks/11")
        GitlabApi.any_instance.stubs(:get).with("/groups/7/hooks/11").returns("id" => 11, "url" => URL, "push_events" => true, "pipeline_events" => false)
        assert Gitlab.register_again?(@row, url: URL)

        following = { "id" => 11, "url" => URL, "push_events" => true, "pipeline_events" => true, "job_events" => true, "deployment_events" => true }
        GitlabApi.any_instance.stubs(:get).with("/groups/7/hooks/11").returns(following)
        assert Gitlab.register_again?(@row, url: URL), "a webhook from before issues were followed hears no labels"

        GitlabApi.any_instance.stubs(:get).with("/groups/7/hooks/11").returns(following.merge("issues_events" => true))
        assert_not Gitlab.register_again?(@row, url: URL)

        GitlabApi.any_instance.stubs(:get).with("/groups/7/hooks/11").raises(GitlabApi::NotFound, "GitLab answered 404")
        assert Gitlab.register_again?(@row, url: URL)
      end

      test "a label added to an issue, or an issue opened with labels, is read with the issue and who did it, and nothing else about an issue is" do
        headers = { "x-gitlab-event" => "Issue Hook" }
        labelled = Gitlab.labelled(issue_hook("update"), headers: headers).sole
        assert_equal [ [ "Firefight" ], "acme/platform/web#23", "Checkout returns 500", "https://gitlab.com/acme/platform/web/-/issues/23", "Since 14:00" ],
                     [ labelled.labels, labelled.issue_key, labelled.issue_title, labelled.issue_url, labelled.text ]
        assert_equal [ "Bob", "bob@example.com", "301:206:2026-10-14T09:00:00Z" ], [ labelled.asker_name, labelled.asker_email, labelled.reference ]

        assert_equal [ %w[Bug Firefight] ], Gitlab.labelled(issue_hook("open", before: nil), headers: headers).map(&:labels)
        assert_nil Gitlab.labelled(issue_hook("update", email: "[REDACTED]"), headers: headers).sole.asker_email, "GitLab may hide who it was"
        assert_empty Gitlab.labelled(issue_hook("update", before: [ [ 205, "Bug" ], [ 206, "Firefight" ] ]), headers: headers), "a label already on it was not added"
        assert_empty Gitlab.labelled(issue_hook("update", before: nil), headers: headers), "a change that left the labels alone added none"
        assert_empty Gitlab.labelled(issue_hook("close", labels: [ [ 205, "Bug" ] ], before: [ [ 205, "Bug" ], [ 206, "Firefight" ] ]), headers: headers)
        assert_empty Gitlab.labelled(issue_hook("update"), headers: { "x-gitlab-event" => "Merge Request Hook" })
        assert_empty Gitlab.labelled(issue_hook("update"), headers: { "x-gitlab-event" => "Confidential Issue Hook" }), "a confidential issue is never followed"
        assert_empty Gitlab.events(issue_hook("update"), headers: headers)
      end

      private

      # An issue event as GitLab documents it (webhook_events.md, Work item events): labels the issue's labels now, and an
      # update's changes.labels the ones before and after. user is who did it.
      def issue_hook(action, labels: [ [ 205, "Bug" ], [ 206, "Firefight" ] ], before: [ [ 205, "Bug" ] ], email: "bob@example.com")
        as_labels = ->(listed) { listed.map { |id, title| { "id" => id, "title" => title } } }
        { "object_kind" => "issue", "event_type" => "issue", "user" => { "name" => "Bob", "username" => "bob", "email" => email },
          "project" => { "path_with_namespace" => "acme/platform/web" }, "labels" => as_labels.(labels),
          "object_attributes" => { "id" => 301, "iid" => 23, "title" => "Checkout returns 500", "description" => "Since 14:00", "action" => action,
                                   "url" => "https://gitlab.com/acme/platform/web/-/issues/23", "updated_at" => "2026-10-14T09:00:00Z" },
          "changes" => (before ? { "labels" => { "previous" => as_labels.(before), "current" => as_labels.(labels) } } : {}) }
      end

      def projects(listed) = GitlabApi.any_instance.stubs(:list).with("/projects", PROJECTS_QUERY, pages: Packs::Gitlab::MAX_PROJECT_PAGES).returns([ listed, false ])

      def project(id, path, namespace, kind: "group") = { "id" => id, "path_with_namespace" => path, "namespace" => { "full_path" => namespace, "kind" => kind } }

      def push(commits, ref: "refs/heads/main", total: nil)
        { "object_kind" => "push", "ref" => ref, "commits" => commits, "total_commits_count" => total || commits.size,
          "project" => { "path_with_namespace" => "acme/platform/web", "default_branch" => "main" } }
      end

      def push_events(files, **)
        Gitlab.events(push([ files ], **), headers: { "x-gitlab-event" => "Push Hook", "idempotency-key" => "retry-safe-id", "x-gitlab-event-uuid" => "event-uuid" })
      end

      def project_event(name)
        Gitlab.events({ "event_name" => name, "path_with_namespace" => "acme/platform/new", "project_id" => 22 }, headers: { "x-gitlab-event" => "Project Hook" })
      end
    end
  end
end
