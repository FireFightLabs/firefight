require "test_helper"

# GitHub's, GitLab's and Bitbucket's changes from the webhook to the map. GitHub's App sends every installation's changes
# to one address, and Firefight registers GitLab's and Bitbucket's webhook with the connection's own token. A signed
# delivery names a repository, which is read again with its infrastructure files, so the map and its suggestions follow.
class LiveUpdatesCodeHostsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include LiveUpdatesTestHelper

  GITHUB_SECRET = "github-app-webhook-secret".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @previous_secret = ENV["INTEGRATION_GITHUB_WEBHOOK_SECRET"]
    ENV["INTEGRATION_GITHUB_WEBHOOK_SECRET"] = GITHUB_SECRET
    # A worker the map already has, which an infrastructure file names.
    ResourceMap::Resource.create!(workspace: @workspace, provider: "cloudflare", account: "acc", kind: ResourceMap::KIND_WORKER, external_id: "edge-api",
                                  name: "edge-api", first_seen_at: 1.day.ago, last_seen_at: 1.day.ago)
  end

  teardown do
    ENV["INTEGRATION_GITHUB_WEBHOOK_SECRET"] = @previous_secret
  end

  test "GitHub: a signed push changing an infrastructure file re-reads the repository and its suggestions, and a deleted repository goes" do
    row = github_row
    assert row.live_updates.on
    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [ github_repository("acme/infra"), github_repository("acme/old") ]))
    Integrations::GithubApp.stubs(:installation_token).returns("ghs_token")
    Integrations::GithubApp.stubs(:get).with("/repos/acme/infra", token: "ghs_token")
                           .returns("full_name" => "acme/infra", "default_branch" => "main", "html_url" => "https://github.com/acme/infra", "size" => 10)
    Integrations::GithubApp.stubs(:get).with("/repos/acme/infra/git/trees/main?recursive=1", token: "ghs_token")
                           .returns("tree" => [ { "type" => "blob", "path" => "edge/wrangler.toml", "sha" => "blob-1", "size" => 40 } ], "truncated" => false)
    Integrations::GithubApp.stubs(:get).with("/repos/acme/infra/git/blobs/blob-1", token: "ghs_token")
                           .returns("encoding" => "base64", "content" => Base64.encode64(%(name = "edge-api")))

    push = github_body("ref" => "refs/heads/main", "commits" => [ { "modified" => [ "edge/wrangler.toml" ] } ],
                       "repository" => { "full_name" => "acme/infra", "default_branch" => "main" })
    post api_v1_app_events_path("github"), params: push, headers: github_headers(push, "push", "d-1").merge("x-hub-signature-256" => "sha256=#{'0' * 64}")
    assert_response :unauthorized
    2.times do
      post api_v1_app_events_path("github"), params: push, headers: github_headers(push, "push", "d-1")
      assert_response :ok
    end
    assert_equal 1, ResourceMap::ReceivedEvent.where(integration_environment: row).count, "a redelivery with the same X-GitHub-Delivery is kept once"

    perform_enqueued_jobs(only: Integrations::MapEventJob)
    suggestion = ResourceMap::Link.find_by!(workspace: @workspace, relation: ResourceMap::RELATION_MANAGED_BY, origin: ResourceMap::ORIGIN_INFERRED)
    assert_equal [ "edge-api", "acme/infra" ], [ suggestion.from_resource.name, suggestion.to_resource.external_id ]

    Integrations::GithubApp.stubs(:get).with("/repos/acme/old", token: "ghs_token").raises(Integrations::GithubApp::NotFound, "GitHub: Not Found")
    deleted = github_body("action" => "deleted", "repository" => { "full_name" => "acme/old" })
    post api_v1_app_events_path("github"), params: deleted, headers: github_headers(deleted, "repository", "d-2")
    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert map_resource("github", "acme/old").removed_at.present?
    assert_nil map_resource("github", "acme/infra").removed_at
  end

  test "GitHub: without the App's webhook secret the address answers nothing and live updates say why" do
    ENV["INTEGRATION_GITHUB_WEBHOOK_SECRET"] = nil
    row = github_row
    body = github_body("action" => "deleted", "repository" => { "full_name" => "acme/old" })

    post api_v1_app_events_path("github"), params: body, headers: github_headers(body, "repository", "d-1")

    assert_response :not_found
    assert_equal "Firefight's GitHub app is not set up to send changes, so the map updates at each sweep.", row.live_updates.reason
  end

  test "GitLab: Firefight registers a group webhook, a delivery with its secret re-reads a project, and removing the connection takes only Firefight's back" do
    row = gitlab_row
    Integrations::GitlabApi.any_instance.stubs(:list).with("/projects", { "membership" => true, "order_by" => "id", "sort" => "asc" }, pages: 10)
                           .returns([ [ gitlab_project(1, "acme/web"), gitlab_project(2, "acme/old") ], false ])
    Integrations::GitlabApi.any_instance.stubs(:get).with("/groups/acme", { "with_projects" => false }).returns("id" => 7)
    Integrations::GitlabApi.any_instance.stubs(:list).with("/groups/7/hooks").returns([ [ { "id" => 3, "url" => "https://example.com/theirs" } ], false ])
    Integrations::GitlabApi.any_instance.expects(:post).with("/groups/7/hooks", has_entries("push_events" => true, "project_events" => true)).returns("id" => 11)
    with_app_host { Integrations::MapEvents.prepare!(row) }
    assert_equal [ "/groups/7/hooks/11", true ], [ row.reload.map_events_webhook_id, row.live_updates.on ]
    assert_equal "register", Ability::Invocation.where(workspace: @workspace, source: AbilityGateway::SOURCE_MAP_SWEEP).sole.params["webhook"]

    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [ gitlab_repository("acme/web"), gitlab_repository("acme/old") ]))
    destroyed = { "event_name" => "project_destroy", "path_with_namespace" => "acme/old", "project_id" => 2 }.to_json
    post api_v1_map_events_path(row.map_events_token), params: destroyed, headers: gitlab_headers("guessed", "Project Hook")
    assert_response :unauthorized
    post api_v1_map_events_path(row.map_events_token), params: destroyed, headers: gitlab_headers(row.map_events_secret, "Project Hook")
    assert_response :ok
    Integrations::GitlabApi.any_instance.stubs(:get).with("/projects/acme%2Fold").raises(Integrations::GitlabApi::NotFound, "GitLab answered 404: 404 Project Not Found")
    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert map_resource("gitlab", "acme/old").removed_at.present?

    Integrations::GitlabApi.any_instance.expects(:delete).with("/groups/7/hooks/11").once.returns(nil)
    Integrations::MapEvents.connection_removed(row.integration)
    assert_nil row.reload.map_events_webhook_id
  end

  test "GitLab: a token without the role for a webhook leaves live updates off with the reason, tried again a day later" do
    row = gitlab_row
    Integrations::GitlabApi.any_instance.stubs(:list).with("/projects", { "membership" => true, "order_by" => "id", "sort" => "asc" }, pages: 10)
                           .returns([ [ gitlab_project(1, "acme/web") ], false ])
    Integrations::GitlabApi.any_instance.stubs(:list).with("/projects/1/hooks").raises(Integrations::GitlabApi::Refused, "GitLab answered 403: 403 Forbidden")
    Integrations::GitlabApi.any_instance.expects(:post).never
    Integrations::GitlabApi.any_instance.expects(:delete).never

    with_app_host { Integrations::MapEvents.prepare!(row) }

    state = row.reload.live_updates
    assert_not state.on
    assert_equal "Firefight could not follow GitLab's changes: GitLab answered 403: 403 Forbidden. #{Integrations::MapEventSources::Gitlab::ROLE_NOTE}. " \
                 "Firefight tries again tomorrow. The map still updates at each sweep.", state.reason
    assert_not row.map_events_registration_due?
  end

  test "Bitbucket: Firefight registers a workspace webhook, a signed push to the main branch re-reads the repository, another branch changes nothing, and a deleted repository goes" do
    row = bitbucket_row
    Integrations::BitbucketApi.any_instance.stubs(:list).with("/workspaces/acme/hooks").returns([ [ { "uuid" => "{theirs}", "url" => "https://example.com/hook" } ], false ])
    Integrations::BitbucketApi.any_instance.expects(:post).with("/workspaces/acme/hooks", has_entries("events" => Integrations::MapEventSources::Bitbucket::EVENTS)).returns("uuid" => "{ours}")
    with_app_host { Integrations::MapEvents.prepare!(row) }
    assert_equal [ "{ours}", true ], [ row.reload.map_events_webhook_id, row.live_updates.on ]

    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [ bitbucket_repository("acme/web", "master"), bitbucket_repository("acme/old", "main") ]))
    Integrations::BitbucketApi.any_instance.stubs(:get).with { |path, *| path == "/repositories/acme/web" }
                              .returns("full_name" => "acme/web", "mainbranch" => { "name" => "main" }, "size" => 0, "links" => { "html" => { "href" => "https://bitbucket.org/acme/web" } })

    feature = bitbucket_push("feature")
    post api_v1_map_events_path(row.map_events_token), params: feature, headers: bitbucket_headers(row, feature, "r-1")
    assert_response :ok
    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert_equal "master", map_resource("bitbucket", "acme/web").details["branch"], "a push to another branch changes nothing"

    main = bitbucket_push("main")
    post api_v1_map_events_path(row.map_events_token), params: main, headers: bitbucket_headers(row, main, "r-2").merge("x-hub-signature" => "sha256=#{'0' * 64}")
    assert_response :unauthorized
    post api_v1_map_events_path(row.map_events_token), params: main, headers: bitbucket_headers(row, main, "r-2")
    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert_equal "main", map_resource("bitbucket", "acme/web").details["branch"]

    Integrations::BitbucketApi.any_instance.stubs(:get).with { |path, *| path == "/repositories/acme/old" }.raises(Integrations::BitbucketApi::NotFound, "Bitbucket answered 404: not found")
    deleted = { "repository" => { "full_name" => "acme/old" } }.to_json
    post api_v1_map_events_path(row.map_events_token), params: deleted, headers: bitbucket_headers(row, deleted, "r-3", event: "repo:deleted")
    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert map_resource("bitbucket", "acme/old").removed_at.present?

    Integrations::BitbucketApi.any_instance.expects(:delete).with("/workspaces/acme/hooks/%7Bours%7D").once.returns(nil)
    Integrations::MapEvents.connection_removed(row.integration)
    assert_nil row.reload.map_events_webhook_id
  end

  private

  def github_row
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    row = integration.integration_environments.create!
    row.store_installation!(42)
    row
  end

  def gitlab_row
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "gitlab", name: "GitLab", slug: "gitlab")
    row = integration.integration_environments.create!
    Integrations::Packs::Gitlab.store_credentials!(row, Integrations::Packs::Gitlab::TOKEN => "glpat-token")
    row
  end

  def bitbucket_row
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "bitbucket", name: "Bitbucket", slug: "bitbucket")
    row = integration.integration_environments.create!
    row.store_fields!(Integrations::Packs::Bitbucket::WORKSPACE => "acme")
    Integrations::Packs::Bitbucket.store_credentials!(row, Integrations::Packs::Bitbucket::TOKEN => "bb-token")
    row
  end

  def github_repository(name) = ResourceMap::Found.new(provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: name, name: name)

  def gitlab_repository(name) = ResourceMap::Found.new(provider: "gitlab", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: name, name: name)

  def bitbucket_repository(name, branch)
    ResourceMap::Found.new(provider: "bitbucket", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: name, name: name, details: { "branch" => branch })
  end

  def gitlab_project(id, path) = { "id" => id, "path_with_namespace" => path, "namespace" => { "full_path" => "acme", "kind" => "group" } }

  def github_body(fields) = fields.merge("installation" => { "id" => 42 }).to_json

  def github_headers(body, event, delivery)
    { "x-github-event" => event, "x-github-delivery" => delivery, "Content-Type" => "application/json",
      "x-hub-signature-256" => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', GITHUB_SECRET, body)}" }
  end

  def gitlab_headers(token, event) = { "x-gitlab-token" => token, "x-gitlab-event" => event, "idempotency-key" => SecureRandom.uuid, "Content-Type" => "application/json" }

  def bitbucket_push(branch)
    { "repository" => { "full_name" => "acme/web" }, "push" => { "changes" => [ { "new" => { "type" => "branch", "name" => branch } } ] } }.to_json
  end

  def bitbucket_headers(row, body, request, event: "repo:push")
    { "x-event-key" => event, "x-request-uuid" => request, "Content-Type" => "application/json",
      "x-hub-signature" => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', row.map_events_secret, body)}" }
  end

  def map_resource(provider, id) = ResourceMap::Resource.find_by!(workspace: @workspace, provider: provider, external_id: id)
end
