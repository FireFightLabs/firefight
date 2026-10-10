require "test_helper"

module Integrations
  module Packs
    # The general read, api_read, of GitHub, GitLab and Bitbucket.
    class CodeHostReadsTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
      end

      test "each code host's api_read only reads, and its provider names the guard it goes through" do
        { "github" => ReadGuards::Github, "gitlab" => ReadGuards::Gitlab, "bitbucket" => ReadGuards::Bitbucket }.each do |key, guard|
          definition = NativePack.for(key).tool_definitions.find { |each| each.name == ApiReads::TOOL }
          assert definition.read_only, key
          assert_equal guard, Provider.for(key).read_guard
        end
        assert_empty Github.missing_access(github_row, ApiReads::TOOL), "api_read needs no permission of its own"
      end

      test "GitHub answers with the page of what was read, the repository's when the answer has none, and secrets as names" do
        row = github_row
        GithubApp.stubs(:installation_token).returns("ghs_token")
        GithubApp.expects(:get).with("/repos/acme/web/environments?per_page=5", token: "ghs_token")
                 .returns("total_count" => 1, "environments" => [ { "name" => "production", "protection_rules" => [ { "type" => "required_reviewers" } ] } ])
        result = Github.new(row.integration).call(ApiReads::TOOL, environment_row: row, arguments: { "path" => "repos/acme/web/environments", "query" => { "per_page" => 5 } })

        assert_match "GitHub answered GET /repos/acme/web/environments?per_page=5.", text(result)
        assert_match "required_reviewers", text(result)
        assert_includes text(result), "https://github.com/acme/web"

        GithubApp.expects(:get).with("/repos/acme/web/hooks", token: "ghs_token").returns([ {
          "id" => 1, "active" => true, "events" => %w[push deployment_status],
          "config" => { "url" => "https://hooks.example.com/t0ken", "content_type" => "json", "secret" => "s3cret" },
          "last_response" => { "code" => 502, "status" => "failed", "message" => "Bad gateway" }
        } ])
        hooks = text(Github.new(row.integration).call(ApiReads::TOOL, environment_row: row, arguments: { "path" => "/repos/acme/web/hooks" }))
        %w[t0ken s3cret].each { |hidden| assert_not_includes hooks, hidden }
        [ "https://hooks.example.com/[hidden]", "deployment_status", "\"active\": true", "\"content_type\": \"json\"", "Bad gateway", "502" ].each do |kept|
          assert_includes hooks, kept
        end
      end

      test "GitHub's refusal for a permission the App lacks says how to grant it, and a download is refused by rule" do
        row = github_row
        GithubApp.stubs(:installation_token).returns("ghs_token")
        GithubApp.stubs(:get).raises(GithubApp::NotPermitted, "GitHub: Resource not accessible by integration")
        pack = Github.new(row.integration)

        error = assert_raises(NativePack::Error) { pack.call(ApiReads::TOOL, environment_row: row, arguments: { "path" => "/repos/acme/web/pages" }) }
        assert_match "Accept new permissions", error.message
        assert_raises(PolicyRefusal) { pack.call(ApiReads::TOOL, environment_row: row, arguments: { "path" => "/repos/acme/web/zipball/main" }) }
      end

      test "GitLab reads inside a project named by its path, takes a path written with /api/v4, and hides variable values" do
        integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "gitlab", name: "GitLab")
        row = integration.integration_environments.create!
        Gitlab.store_credentials!(row, Gitlab::TOKEN => "glpat-token")
        pack = Gitlab.new(integration)
        GitlabApi.any_instance.expects(:read).with("/projects/acme%2Fplatform%2Fweb/environments", { "per_page" => "20" })
                 .returns([ { "id" => 1, "name" => "production", "state" => "available" } ])
        result = pack.call(ApiReads::TOOL, environment_row: row, arguments: { "project" => "acme/platform/web", "path" => "/environments", "query" => { "per_page" => 20 } })

        assert_match "production", text(result)
        assert_includes text(result), "https://gitlab.com/acme/platform/web"

        GitlabApi.any_instance.expects(:read).with("/projects/12/variables", {}).returns([ { "key" => "DATABASE_URL", "value" => "postgres://u:pw@h/db" } ])
        shown = text(pack.call(ApiReads::TOOL, environment_row: row, arguments: { "path" => "/api/v4/projects/12/variables" }))
        assert_includes shown, "DATABASE_URL"
        assert_not_includes shown, "pw@h"

        assert_raises(PolicyRefusal) { pack.call(ApiReads::TOOL, environment_row: row, arguments: { "path" => "/projects/12/terraform/state/prod" }) }
        assert_raises(NativePack::Error) { pack.call(ApiReads::TOOL, environment_row: row, arguments: { "project" => "../x", "path" => "/environments" }) }
      end

      test "Bitbucket keeps a read to the workspaces the connection reads, and links the repository's page" do
        integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "bitbucket", name: "Code")
        row = integration.integration_environments.create!
        Bitbucket.store_credentials!(row, Bitbucket::TOKEN => "bb-token")
        row.store_fields!(Bitbucket::WORKSPACE => %w[acme])
        pack = Bitbucket.new(integration)
        BitbucketApi.any_instance.expects(:read).with("/repositories/acme/web/environments", {}).returns("values" => [ { "name" => "Production" } ])

        result = pack.call(ApiReads::TOOL, environment_row: row, arguments: { "path" => "/repositories/acme/web/environments" })
        assert_match "Production", text(result)
        assert_includes text(result), "https://bitbucket.org/acme/web"

        BitbucketApi.any_instance.expects(:read).never
        assert_match "reaches beta", assert_raises(PolicyRefusal) { pack.call(ApiReads::TOOL, environment_row: row, arguments: { "path" => "/repositories/beta/web" }) }.message
        assert_match "names one", assert_raises(PolicyRefusal) { pack.call(ApiReads::TOOL, environment_row: row, arguments: { "path" => "/user/workspaces" }) }.message
      end

      test "Bitbucket reaches any path when the connection reads every workspace" do
        integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "bitbucket", name: "Code")
        row = integration.integration_environments.create!
        Bitbucket.store_credentials!(row, Bitbucket::TOKEN => "bb-token")
        row.store_fields!(Bitbucket::WORKSPACE => [ IntegrationProvider::ConnectField::ALL ])
        BitbucketApi.any_instance.expects(:read).with("/user/workspaces", {}).returns("values" => [ { "workspace" => { "slug" => "acme" } } ])

        assert_match "acme", text(Bitbucket.new(integration).call(ApiReads::TOOL, environment_row: row, arguments: { "path" => "/user/workspaces" }))
      end

      private

      def github_row
        integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
        integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
      end

      def text(result) = Array(result.is_a?(Hash) ? result["content"] : [ { "text" => result } ]).map { |part| part["text"] }.join("\n")
    end
  end
end
