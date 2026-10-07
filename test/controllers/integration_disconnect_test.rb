require "test_helper"

# Disconnecting a connection made through an app installed on the provider's account, which can also remove the app there.
class IntegrationDisconnectTest < ActionDispatch::IntegrationTest
  PAGE = "https://github.com/organizations/acme/settings/installations/42".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    @integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = @integration.integration_environments.create!
    @row.store_installation!("42")
    @row.installation_checked!(Integrations::Installations::Installation.new(account: "acme", page: PAGE, access: { "contents" => "read" }))
    @tool = @integration.tools.create!(name: "rerun_workflow", read_only: false, enabled: true)
  end

  test "the page offers removing the app, ticked unless another connection uses it, and marks a tool lacking a permission" do
    get integrations_url, headers: inertia_headers

    github = inertia_props["integrations"].find { |integration| integration["id"] == @integration.id }
    assert_equal [ { "installationId" => "42", "label" => "Also remove the Firefight app from acme on GitHub", "page" => PAGE, "blockedReason" => nil } ],
                 github["installations"]
    assert_equal "Needs Actions read and write in the GitHub App.", github["tools"].sole["accessMissing"]
    assert_equal({ "app" => "GitHub App", "account" => "acme", "page" => PAGE, "state" => nil, "label" => nil, "reason" => nil },
                 github["environments"].sole["installation"])

    other = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub staging")
    other.integration_environments.create!.store_installation!("42")
    get integrations_url, headers: inertia_headers
    github = inertia_props["integrations"].find { |integration| integration["id"] == @integration.id }
    assert_equal "GitHub staging also uses this installation, so the app stays on GitHub.", github["installations"].sole["blockedReason"]
  end

  test "disconnecting with the app ticked removes it from the account and says so" do
    Integrations::GithubApp.expects(:uninstall).with(@row).returns(true)

    delete integration_url(@integration), params: { uninstall: [ "42" ] }

    assert_redirected_to integrations_path
    assert_equal "GitHub is disconnected. Firefight's app was removed from acme on GitHub.", flash[:notice]
    assert_empty flash[:inertia].to_h["links"].to_a
    assert @integration.reload.deleted?
    assert_nil @row.reload.installation_id
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: IntegrationEnvironment::UNINSTALL_ACTION_KEY, source: AbilityGateway::SOURCE_WEB)
  end

  test "disconnecting with it unticked leaves the app and links to its settings on GitHub" do
    Integrations::GithubApp.expects(:uninstall).never

    delete integration_url(@integration)

    assert_equal "GitHub is disconnected. Firefight's app is still installed on acme. Remove it on GitHub if you no longer need it.", flash[:notice]
    assert_equal [ { "label" => "Open acme on GitHub", "url" => PAGE } ], flash[:inertia]["links"].map(&:stringify_keys)
    assert_nil @row.reload.installation_id
  end

  test "an installation another workspace's connection uses is never removed, whatever was sent" do
    elsewhere = workspaces(:slack_workspace_two).integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    elsewhere.integration_environments.create!.store_installation!("42")
    Integrations::GithubApp.expects(:uninstall).never

    delete integration_url(@integration), params: { uninstall: [ "42" ] }

    assert_equal "GitHub is disconnected. A connection in another Firefight workspace uses this installation, so the app stays on GitHub.", flash[:notice]
    assert_equal "42", elsewhere.integration_environments.sole.installation_id
  end

  test "an app GitHub refused to remove is said with GitHub's words and a link, and the connection is still disconnected" do
    Integrations::GithubApp.expects(:uninstall).raises(Integrations::GithubApp::Error, "GitHub: Forbidden")

    delete integration_url(@integration), params: { uninstall: [ "42" ] }

    assert_equal "Firefight could not remove its app from acme on GitHub: GitHub: Forbidden. Remove it there.", flash[:alert]
    assert_equal "GitHub is disconnected.", flash[:notice]
    assert_equal PAGE, flash[:inertia]["links"].sole.stringify_keys["url"]
    assert @integration.reload.deleted?
  end

  test "a connection that was not made through an app says it is disconnected" do
    sentry = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry", settings: { "server_url" => "https://mcp.sentry.example/mcp" })
    sentry.integration_environments.create!

    delete integration_url(sentry)

    assert_redirected_to integrations_path
    assert_equal "Disconnected Sentry.", flash[:notice]
    assert sentry.reload.deleted?
  end
end
