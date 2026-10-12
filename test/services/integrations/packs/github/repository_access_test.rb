require "test_helper"

module Integrations
  module Packs
    class Github
      class RepositoryAccessTest < ActiveSupport::TestCase
        COLLABORATORS = "/repos/acme/web/collaborators?affiliation=all&page=1&per_page=100".freeze

        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "people, teams and outside collaborators are shown with their roles" do
          GithubApp.stubs(:get).with("/repos/acme/web", token: "ghs_token").returns("owner" => { "login" => "acme", "type" => "Organization" })
          GithubApp.stubs(:get).with(COLLABORATORS, token: "ghs_token")
                   .returns([ { "login" => "ada", "role_name" => "admin" }, { "login" => "grace", "permissions" => { "pull" => true, "push" => true, "admin" => false } } ])
          GithubApp.stubs(:get).with("/orgs/acme/outside_collaborators?per_page=100&page=1", token: "ghs_token").returns([ { "login" => "grace" } ])
          GithubApp.stubs(:get).with("/repos/acme/web/teams?per_page=100", token: "ghs_token").returns([ { "slug" => "sre", "permission" => "maintain" } ])

          text = text_of(@pack.repository_access(environment_row: @row, arguments: { "repo" => "acme/web" }))

          assert_includes text, "People with access to acme/web:\n  ada  admin\n  grace  push  outside collaborator"
          assert_includes text, "Teams with access:\n  sre  maintain"
          assert text.end_with?("https://github.com/acme/web/settings/access")
        end

        test "what the App's permissions do not show is said, and the people are still listed" do
          GithubApp.stubs(:get).with("/repos/acme/web", token: "ghs_token").returns("owner" => { "login" => "acme", "type" => "Organization" })
          GithubApp.stubs(:get).with(COLLABORATORS, token: "ghs_token").returns([ { "login" => "ada", "role_name" => "write" } ])
          GithubApp.stubs(:get).with("/orgs/acme/outside_collaborators?per_page=100&page=1", token: "ghs_token").raises(GithubApp::NotPermitted, "Resource not accessible by integration")
          GithubApp.stubs(:get).with("/repos/acme/web/teams?per_page=100", token: "ghs_token").raises(GithubApp::NotPermitted, "Resource not accessible by integration")

          text = text_of(@pack.repository_access(environment_row: @row, arguments: { "repo" => "acme/web" }))

          assert_includes text, "  ada  write"
          assert_includes text, "Teams not shown: Firefight's GitHub App needs Administration read for them."
          assert_includes text, "Outside collaborators not marked: Firefight's GitHub App needs Members read on the organization for them."
          assert Github.tool_definitions.find { |tool| tool.name == "repository_access" }.read_only
        end

        private

        def text_of(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end
    end
  end
end
