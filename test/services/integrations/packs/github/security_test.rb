require "test_helper"

module Integrations
  module Packs
    class Github
      class SecurityTest < ActiveSupport::TestCase
        SECRET = "ghp_#{'z' * 36}".freeze

        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "Dependabot alerts are listed most severe first, and one is read in full" do
          GithubApp.expects(:get).with("/repos/acme/web/dependabot/alerts?per_page=20&state=open", token: "ghs_token").returns([ alert(1, "low"), alert(2, "critical") ])

          text = text_of(@pack.dependabot_alerts(environment_row: @row, arguments: { "repo" => "acme/web" }))

          assert_operator text.index("#2 open  critical"), :<, text.index("#1 open  low")
          assert text.end_with?("https://github.com/acme/web/security/dependabot")

          GithubApp.stubs(:get).with("/repos/acme/web/dependabot/alerts/2", token: "ghs_token")
                   .returns(alert(2, "critical").merge("security_advisory" => alert(2, "critical")["security_advisory"].merge("description" => "Crafted headers exhaust memory.")))
          text = text_of(@pack.dependabot_alert(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 2 }))
          assert_includes text, "Crafted headers exhaust memory."
          assert text.end_with?("https://github.com/acme/web/security/dependabot/2")
        end

        test "an open Dependabot alert is dismissed with its reason, and only a dismissed one reopens" do
          GithubApp.stubs(:get).with("/repos/acme/web/dependabot/alerts/2", token: "ghs_token").returns(alert(2, "high"))
          GithubApp.expects(:write).with(:patch, "/repos/acme/web/dependabot/alerts/2", { state: "dismissed", dismissed_reason: "not_used", dismissed_comment: "Dev only" }, token: "ghs_token").returns({})

          text = text_of(@pack.dismiss_dependabot_alert(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 2, "reason" => "not_used", "comment" => "Dev only" }))

          assert_includes text, "Dismissed Dependabot alert 2 (rack, GHSA-2) in acme/web as not used. reopen_dependabot_alert opens it again."
          assert_equal "Dependabot alert 2 in acme/web is open, and only a dismissed one is reopened.",
                       assert_raises(NativePack::Error) { @pack.reopen_dependabot_alert(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 2 }) }.message
          assert_match "reason must be one of", assert_raises(NativePack::Error) {
            @pack.dismiss_dependabot_alert(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 2, "reason" => "because" })
          }.message
          assert_match "longer than GitHub takes, 280 characters", assert_raises(NativePack::Error) {
            @pack.dismiss_dependabot_alert(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 2, "reason" => "not_used", "comment" => "x" * 281 })
          }.message
        end

        test "code scanning alerts name the rule and where it is" do
          GithubApp.expects(:get).with("/repos/acme/web/code-scanning/alerts?per_page=20&ref=main&state=open", token: "ghs_token").returns([
            { "number" => 4, "state" => "open", "html_url" => "https://github.com/acme/web/security/code-scanning/4", "tool" => { "name" => "CodeQL" },
              "rule" => { "id" => "js/sql-injection", "name" => "SQL injection", "security_severity_level" => "high" },
              "most_recent_instance" => { "location" => { "path" => "app/db.js", "start_line" => 12 }, "message" => { "text" => "Query built from input" } } }
          ])

          text = text_of(@pack.code_scanning_alerts(environment_row: @row, arguments: { "repo" => "acme/web", "ref" => "main" }))

          assert_includes text, "#4 open  high  SQL injection  CodeQL  app/db.js:12  Query built from input  https://github.com/acme/web/security/code-scanning/4"
        end

        test "secret scanning asks GitHub to hide the secret and never says it, even when GitHub sends it" do
          GithubApp.expects(:get).with("/repos/acme/web/secret-scanning/alerts?hide_secret=true&per_page=20&state=open", token: "ghs_token").returns([ secret_alert ])
          text = text_of(@pack.secret_scanning_alerts(environment_row: @row, arguments: { "repo" => "acme/web" }))
          assert_includes text, "#3 open  GitHub Personal Access Token  found t0  still works, pushed past push protection  https://github.com/acme/web/security/secret-scanning/3"
          assert_not_includes text, SECRET

          GithubApp.expects(:get).with("/repos/acme/web/secret-scanning/alerts/3?hide_secret=true", token: "ghs_token").returns(secret_alert)
          text = text_of(@pack.secret_scanning_alert(environment_row: @row, arguments: { "repo" => "acme/web", "number" => 3 }))
          assert_includes text, "First found in config/app.yml:4 in commit #{'d' * 12}"
          assert_not_includes text, SECRET
        end

        test "a repository whose alerts GitHub answers not found says scanning may be off, and a missing permission is named" do
          GithubApp.stubs(:get).with("/repos/acme/web/code-scanning/alerts?per_page=20&state=open", token: "ghs_token").raises(GithubApp::NotFound, "GitHub: no analysis found")
          assert_match "GitHub has no code scanning for acme/web. Code scanning may not be set up there.",
                       assert_raises(NativePack::Error) { @pack.code_scanning_alerts(environment_row: @row, arguments: { "repo" => "acme/web" }) }.message

          GithubApp.stubs(:get).with("/repos/acme/web/dependabot/alerts?per_page=20&state=open", token: "ghs_token").raises(GithubApp::NotPermitted, "GitHub: Resource not accessible by integration")
          assert_match "Firefight's GitHub App needs Dependabot alerts read on this installation for that.",
                       assert_raises(NativePack::Error) { @pack.dependabot_alerts(environment_row: @row, arguments: { "repo" => "acme/web" }) }.message
        end

        private

        def alert(number, severity)
          { "number" => number, "state" => "open", "html_url" => "https://github.com/acme/web/security/dependabot/#{number}",
            "dependency" => { "package" => { "name" => "rack", "ecosystem" => "rubygems" }, "manifest_path" => "Gemfile.lock" },
            "security_advisory" => { "ghsa_id" => "GHSA-#{number}", "summary" => "Denial of service", "severity" => severity },
            "security_vulnerability" => { "vulnerable_version_range" => "< 2.2.8", "first_patched_version" => { "identifier" => "2.2.8" } } }
        end

        def secret_alert
          { "number" => 3, "state" => "open", "secret_type" => "github_personal_access_token", "secret_type_display_name" => "GitHub Personal Access Token",
            "secret" => SECRET, "validity" => "active", "push_protection_bypassed" => true, "created_at" => "t0",
            "html_url" => "https://github.com/acme/web/security/secret-scanning/3",
            "first_location_detected" => { "path" => "config/app.yml", "start_line" => 4, "commit_sha" => "d" * 40 } }
        end

        def text_of(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end
    end
  end
end
