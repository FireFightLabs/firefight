require "test_helper"

# What GitHub's App sends about an installation itself: removed, suspended and unsuspended, new permissions accepted, and
# repositories taken away. Each reaches every connection made through that installation.
class GithubInstallationEventsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SECRET = "github-app-webhook-secret".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @previous_secret = ENV["INTEGRATION_GITHUB_WEBHOOK_SECRET"]
    ENV["INTEGRATION_GITHUB_WEBHOOK_SECRET"] = SECRET
    @row = github_row(@workspace, "GitHub")
    @other = github_row(workspaces(:slack_workspace_two), "GitHub")
    @row.installation_checked!(Integrations::Installations::Installation.new(account: "acme", access: { "contents" => "read" }))
    [ @row, @other ].each { |row| cache_token(row) }
  end

  teardown do
    ENV["INTEGRATION_GITHUB_WEBHOOK_SECRET"] = @previous_secret
  end

  def github_row(workspace, name)
    integration = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: name)
    row = integration.integration_environments.create!
    row.store_installation!(42)
    row
  end

  def cache_token(row) = row.store_credential!(Integrations::GithubApp::TOKEN_CACHE_KEY, "token" => "ghs_old", "expires_at" => 1.hour.from_now.iso8601)

  def cached?(row) = row.reload.credentials_hash.key?(Integrations::GithubApp::TOKEN_CACHE_KEY)

  def deliver(event, fields)
    body = fields.merge("installation" => { "id" => 42 }).to_json
    post api_v1_app_events_path("github"), params: body, headers: {
      "x-github-event" => event, "x-github-delivery" => SecureRandom.uuid, "Content-Type" => "application/json",
      "x-hub-signature-256" => "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', SECRET, body)}"
    }
    assert_response :ok
  end

  test "new permissions accepted drops the cached token on every connection made through the installation and reads it again" do
    assert_enqueued_jobs 2, only: Integrations::InstallationCheckJob do
      deliver("installation", "action" => "new_permissions_accepted")
    end

    assert_not cached?(@row)
    assert_not cached?(@other)
    Integrations::GithubApp.stubs(:installation).returns("account" => { "login" => "acme" }, "permissions" => { "actions" => "read" }, "suspended_at" => nil)
    Integrations::GithubApp.stubs(:installation_token).returns("ghs_new")
    Integrations::GithubApp.stubs(:get).with("/installation/repositories?per_page=1", token: "ghs_new").returns("total_count" => 1)
    perform_enqueued_jobs(only: Integrations::InstallationCheckJob)
    assert_equal({ "actions" => "read" }, @row.reload.installation_access)
  end

  test "a removal on GitHub marks the connections, stops their tools and live updates, and Reconnect starts from nothing" do
    deliver("installation", "action" => "deleted")

    assert_equal "Removed on GitHub", Integrations::Installations.state_label(@row.reload)
    assert_not cached?(@row)
    assert_not @row.live_updates.on
    assert_match(/removed from acme on GitHub/, @row.live_updates.reason)

    push = { "ref" => "refs/heads/main", "commits" => [], "repository" => { "full_name" => "acme/infra", "default_branch" => "main" } }
    assert_no_enqueued_jobs(only: Integrations::MapEventJob) { deliver("push", push) }
  end

  test "a suspension stops the connections and unsuspending restores them" do
    deliver("installation", "action" => "suspend")
    assert_equal [ "suspended", "suspended" ], [ @row.reload.installation_state, @other.reload.installation_state ]

    cache_token(@row)
    assert_enqueued_jobs 2, only: Integrations::MapSweepJob do
      deliver("installation", "action" => "unsuspend")
    end
    assert_nil @row.reload.installation_state
    assert_not cached?(@row)
  end

  test "repositories taken away read the installation again, and none left marks it, while one added restores it" do
    Integrations::GithubApp.stubs(:installation).returns("account" => { "login" => "acme" }, "suspended_at" => nil)
    Integrations::GithubApp.stubs(:installation_token).returns("ghs_token")
    Integrations::GithubApp.stubs(:get).with("/installation/repositories?per_page=1", token: "ghs_token").returns("total_count" => 0)

    perform_enqueued_jobs(only: Integrations::InstallationCheckJob) do
      deliver("installation_repositories", "action" => "removed", "repository_selection" => "selected", "repositories_removed" => [ { "full_name" => "acme/web" } ])
    end
    assert_equal "No repositories on GitHub", Integrations::Installations.state_label(@row.reload)
    assert cached?(@row), "what an installation shares is not what its token may do"

    Integrations::GithubApp.stubs(:get).with("/installation/repositories?per_page=1", token: "ghs_token").returns("total_count" => 1)
    perform_enqueued_jobs(only: Integrations::InstallationCheckJob) do
      deliver("installation_repositories", "action" => "added", "repositories_added" => [ { "full_name" => "acme/web" } ])
    end
    assert_nil @row.reload.installation_state
  end
end
