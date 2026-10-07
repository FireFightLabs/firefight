require "test_helper"

module Integrations
  module Packs
    class Github
      class ChecksTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "a ref's checks and statuses are read failing first, linked to the commit they ran on" do
          GithubApp.stubs(:get).with("/repos/acme/web", token: "ghs_token").returns("default_branch" => "main")
          GithubApp.stubs(:get).with("/repos/acme/web/commits/main/check-runs?filter=latest&per_page=100", token: "ghs_token").returns("check_runs" => [
            { "name" => "lint", "status" => "completed", "conclusion" => "success", "html_url" => "https://github.com/acme/web/runs/1", "head_sha" => "a" * 40 },
            { "name" => "test", "status" => "completed", "conclusion" => "timed_out", "html_url" => "https://github.com/acme/web/runs/2", "head_sha" => "a" * 40 }
          ])
          GithubApp.stubs(:get).with("/repos/acme/web/commits/main/status?per_page=100", token: "ghs_token")
                   .raises(GithubApp::NotPermitted, "GitHub: Resource not accessible by integration")

          text = text_of(@pack.ref_checks(environment_row: @row, arguments: { "repo" => "acme/web" }))

          assert_includes text, "Checks on main:\n  test: timed_out  https://github.com/acme/web/runs/2\n  lint: success"
          assert_includes text, "Commit statuses not shown: Firefight's GitHub App needs Commit statuses read for them."
          assert text.end_with?("https://github.com/acme/web/commit/#{'a' * 40}")
        end

        private

        def text_of(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end
    end
  end
end
