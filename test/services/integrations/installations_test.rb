require "test_helper"

module Integrations
  class InstallationsTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    PAGE = "https://github.com/organizations/acme/settings/installations/42".freeze

    setup do
      @workspace = workspaces(:slack_workspace_one)
      @row = github_row(@workspace, "GitHub")
      @row.installation_checked!(Installations::Installation.new(account: "acme", page: PAGE, access: { "contents" => "read", "metadata" => "read" }))
      @tool = @row.integration.tools.create!(name: "workflow_runs", read_only: true, enabled: true)
    end

    def github_row(workspace, name, installation: "42")
      integration = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: name)
      row = integration.integration_environments.create!
      row.store_installation!(installation)
      row
    end

    def found(state: nil, access: { "contents" => "read" }) = { "account" => { "login" => "acme" }, "html_url" => PAGE, "permissions" => access, "suspended_at" => state }

    test "a tool needing a permission the installation lacks is marked, answers why without calling GitHub, and a grant lifts it" do
      assert_equal "Needs Actions read in the GitHub App.", @tool.access_missing_reason
      assert_match(/\ANeeds Actions read in the GitHub App\./, Mcp::ConnectionToolFactory.description_for(@tool))
      Packs::Github.any_instance.expects(:workflow_runs).never
      GithubApp.stubs(:installation).returns(found)
      GithubApp.stubs(:installation_token).returns("ghs_token")
      GithubApp.stubs(:get).returns("total_count" => 1)

      travel 2.minutes do
        result = NativeExecutor.call(tool: @tool, environment_row: @row, arguments: { "repo" => "acme/web" })
        assert result["isError"]
        assert_equal "github_workflow_runs was not run. It needs Actions read in the GitHub App, which acme has not granted. An owner grants it in the " \
                     "app's settings on GitHub at #{PAGE}. Tell the person rather than guessing.", result["content"].first["text"]
      end

      @row.store_installation_access!("actions" => "write", "contents" => "read")
      assert_nil @tool.reload.access_missing_reason, "write covers read"
    end

    test "a pull request change the installation was not granted is answered without calling GitHub" do
      tool = @row.integration.tools.create!(name: "close_pull_request", read_only: false, enabled: true)
      Packs::Github.any_instance.expects(:close_pull_request).never
      GithubApp.stubs(:installation).returns(found)
      GithubApp.stubs(:installation_token).returns("ghs_token")
      GithubApp.stubs(:get).returns("total_count" => 1)

      travel 2.minutes do
        result = NativeExecutor.call(tool: tool, environment_row: @row, arguments: { "repo" => "acme/web", "number" => 4 })
        assert result["isError"]
        assert_match "github_close_pull_request was not run. It needs Pull requests read and write in the GitHub App", result["content"].first["text"]
      end
    end

    test "a refusal read a while ago is read again first, so a permission an owner just accepted runs the tool" do
      GithubApp.expects(:installation).returns(found(access: { "actions" => "read", "contents" => "read" }))
      GithubApp.stubs(:installation_token).returns("ghs_token")
      GithubApp.stubs(:get).returns("total_count" => 1)

      travel 2.minutes do
        assert_nil Installations.refusal(@row, @tool)
      end
      assert_equal "read", @row.reload.installation_access["actions"]
    end

    test "every GitHub tool says what it needs, so a new one cannot be left unchecked" do
      assert_equal Packs::Github.tool_definitions.map(&:name).sort, Packs::Github::NEEDS.keys.sort
      assert_equal [ "Actions read and write" ], Packs::Github.missing_access(@row, "rerun_workflow")
      assert_equal [], Packs::Github.missing_access(@row, "fetch_file")
      assert_equal [ "Contents read and write", "Pull requests read" ], Packs::Github.missing_access(@row, "merge_pull_request")
      assert_equal [ "Dependabot alerts read and write" ], Packs::Github.missing_access(@row, "dismiss_dependabot_alert")
      assert_equal [ "Secret scanning alerts read" ], Packs::Github.missing_access(@row, "secret_scanning_alerts")
      assert_equal [ "Issues read and write" ], Packs::Github.missing_access(@row, "close_issue")
    end

    test "reading the installation marks it removed, suspended or sharing nothing, and back once it works again" do
      GithubApp.stubs(:installation_token).returns("ghs_token")
      GithubApp.stubs(:installation).returns(nil)
      Installations.check!(@row)
      assert_equal [ Installations::REMOVED, "acme" ], [ @row.reload.installation_state, @row.installation_account ]
      assert_match(/\AFirefight's app was removed from acme on GitHub/, Installations.stopped_reason(@row))
      assert_equal "Removed on GitHub", Installations.state_label(@row)

      GithubApp.stubs(:installation).returns(found(state: 1.hour.ago.iso8601))
      Installations.check!(@row)
      assert_equal "Suspended on GitHub", Installations.state_label(@row.reload)

      GithubApp.stubs(:installation).returns(found)
      GithubApp.stubs(:get).with("/installation/repositories?per_page=1", token: "ghs_token").returns("total_count" => 0)
      Installations.check!(@row)
      assert_equal "No repositories on GitHub", Installations.state_label(@row.reload)

      GithubApp.stubs(:get).with("/installation/repositories?per_page=1", token: "ghs_token").returns("total_count" => 2)
      assert_enqueued_with(job: MapSweepJob) { Installations.check!(@row) }
      assert_nil @row.reload.installation_state
    end

    test "a stopped installation stops the tools, the map's reads and live updates, and leaves the map as it was" do
      ENV["INTEGRATION_GITHUB_WEBHOOK_SECRET"], previous = "secret", ENV["INTEGRATION_GITHUB_WEBHOOK_SECRET"]
      @row.installation_marked!(Installations::SUSPENDED)
      Packs::Github.any_instance.expects(:map_of).never

      assert_match(/\Agithub_workflow_runs was not run\. Firefight's app is suspended on acme on GitHub/,
                   NativeExecutor.call(tool: @tool, environment_row: @row, arguments: {})["content"].first["text"])
      assert_not MapSweep.run!(@row)
      assert_match(/suspended on acme/, @row.reload.map_error)
      assert_not @row.live_updates.on
      assert_match(/suspended on acme/, @row.live_updates.reason)
      assert_not IntegrationEnvironment.reachable.exists?(id: @row.id)
    ensure
      ENV["INTEGRATION_GITHUB_WEBHOOK_SECRET"] = previous
    end

    test "the health check reads the installation, so one removed on GitHub fails with why" do
      GithubApp.stubs(:installation).returns(nil)
      GithubApp.expects(:installation_token).never

      assert_not HealthCheckService.check!(@row)
      assert_match(/removed from acme on GitHub/, @row.reload.health_error)
    end

    test "a removal or suspension on GitHub is taken as said and the cached token dropped, and anything else is read again" do
      @row.store_credential!(GithubApp::TOKEN_CACHE_KEY, "token" => "ghs_old", "expires_at" => 1.hour.from_now.iso8601)
      Installations.changed!(@row, Installations::CHANGE_SUSPENDED)
      assert_equal Installations::SUSPENDED, @row.reload.installation_state
      assert_nil @row.credentials_hash[GithubApp::TOKEN_CACHE_KEY]

      assert_enqueued_with(job: InstallationCheckJob) { Installations.changed!(@row, Installations::CHANGE_RESTORED) }
      assert_nil @row.reload.installation_state

      @row.store_credential!(GithubApp::TOKEN_CACHE_KEY, "token" => "ghs_old", "expires_at" => 1.hour.from_now.iso8601)
      assert_enqueued_with(job: InstallationCheckJob) { Installations.changed!(@row, Installations::CHANGE_ACCESS) }
      assert_nil @row.reload.credentials_hash[GithubApp::TOKEN_CACHE_KEY]

      Installations.changed!(@row, Installations::CHANGE_REMOVED)
      assert_equal Installations::REMOVED, @row.reload.installation_state
    end

    test "disconnecting removes the app from the account when asked, in the activity log as the person's, and forgets the installation" do
      membership = workspace_memberships(:alice_workspace_one)
      @row.store_credential!(GithubApp::TOKEN_CACHE_KEY, "token" => "ghs_old", "expires_at" => 1.hour.from_now.iso8601)
      GithubApp.expects(:uninstall).with(@row).returns(true)

      done = Installations.disconnected!(@row.integration, uninstall: [ "42" ], by: membership).sole

      assert done.removed
      assert_equal "Firefight's app was removed from acme on GitHub.", done.words
      assert_nil done.link
      entry = Ability::Invocation.find_by!(workspace: @workspace, action_key: IntegrationEnvironment::UNINSTALL_ACTION_KEY, source: AbilityGateway::SOURCE_WEB)
      assert_equal [ "uninstall", "acme", Ability::Invocation::OUTCOME_SUCCESS ], [ entry.params["app"], entry.params["account"], entry.outcome ]
      @row.reload
      assert_nil @row.installation_id
      assert_nil @row.credentials_hash[GithubApp::TOKEN_CACHE_KEY]
    end

    test "disconnecting without removing the app forgets it and links to its settings on GitHub" do
      GithubApp.expects(:uninstall).never

      done = Installations.disconnected!(@row.integration, uninstall: [], by: workspace_memberships(:alice_workspace_one)).sole

      assert_not done.removed
      assert_equal "Firefight's app is still installed on acme. Remove it on GitHub if you no longer need it.", done.words
      assert_equal({ label: "Open acme on GitHub", url: PAGE }, done.link)
      assert_nil @row.reload.installation_id
    end

    test "an installation another connection uses is never removed, here or in another workspace" do
      GithubApp.expects(:uninstall).never
      other = github_row(@workspace, "GitHub staging")
      assert_equal "GitHub staging also uses this installation, so the app stays on GitHub.", @row.uninstall_blocked_reason

      other.integration.update!(deleted_at: Time.current)
      elsewhere = github_row(workspaces(:slack_workspace_two), "GitHub")
      assert_equal "A connection in another Firefight workspace uses this installation, so the app stays on GitHub.", @row.uninstall_blocked_reason

      done = Installations.disconnected!(@row.integration, uninstall: [ "42" ], by: workspace_memberships(:alice_workspace_one)).sole
      assert_not done.removed
      assert_nil done.link, "the settings page would only offer to break the other connection"
      assert_equal "42", elsewhere.reload.installation_id
    end

    test "connecting through a new installation starts from nothing known of the old one" do
      @row.installation_marked!(Installations::REMOVED)
      @row.store_credential!(GithubApp::TOKEN_CACHE_KEY, "token" => "ghs_old", "expires_at" => 1.hour.from_now.iso8601)

      Installations.connected!(@row, "99")

      @row.reload
      assert_equal [ "99", nil, nil, {} ], [ @row.installation_id, @row.installation_state, @row.credentials_hash[GithubApp::TOKEN_CACHE_KEY], @row.installation_details ]
    end
  end
end
