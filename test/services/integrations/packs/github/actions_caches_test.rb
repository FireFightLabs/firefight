require "test_helper"

module Integrations
  module Packs
    class Github
      class ActionsCachesTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "caches with a key are cleared, held to a branch when one is named" do
          GithubApp.expects(:write).with(:delete, "/repos/acme/web/actions/caches?key=npm-linux-abc&ref=refs%2Fheads%2Fmain", token: "ghs_token")
                   .returns("total_count" => 1, "actions_caches" => [ { "id" => 1, "key" => "npm-linux-abc", "ref" => "refs/heads/main", "size_in_bytes" => 1024 } ])

          text = text_of(@pack.clear_actions_cache(environment_row: @row, arguments: { "repo" => "acme/web", "key" => "npm-linux-abc", "ref" => "main" }))

          assert_includes text, "Cleared 1 Actions cache key npm-linux-abc on refs/heads/main in acme/web, 1024 bytes:\n  npm-linux-abc  refs/heads/main  1024 bytes"
          assert text.end_with?("https://github.com/acme/web/actions/caches")
        end

        test "every cache made on a ref is cleared one by one" do
          GithubApp.expects(:get).with("/repos/acme/web/actions/caches?page=1&per_page=100&ref=refs%2Fpull%2F412%2Fmerge", token: "ghs_token")
                   .returns("actions_caches" => [ { "id" => 1, "key" => "a", "ref" => "refs/pull/412/merge", "size_in_bytes" => 10 },
                                                  { "id" => 2, "key" => "b", "ref" => "refs/pull/412/merge", "size_in_bytes" => 20 } ])
          GithubApp.expects(:write).with(:delete, "/repos/acme/web/actions/caches/1", token: "ghs_token").returns({})
          GithubApp.expects(:write).with(:delete, "/repos/acme/web/actions/caches/2", token: "ghs_token").returns({})

          text = text_of(@pack.clear_actions_cache(environment_row: @row, arguments: { "repo" => "acme/web", "ref" => "refs/pull/412/merge" }))

          assert text.start_with?("Cleared 2 Actions caches on refs/pull/412/merge in acme/web, 30 bytes:")
        end

        test "neither a key nor a ref clears nothing, and it is a change needing Actions write" do
          GithubApp.expects(:write).never
          error = assert_raises(PolicyRefusal) { @pack.clear_actions_cache(environment_row: @row, arguments: { "repo" => "acme/web" }) }
          assert_equal "Give a cache's key or a ref, since Firefight never clears every cache in a repository at once.", error.message
          assert_not Github.tool_definitions.find { |tool| tool.name == "clear_actions_cache" }.read_only
          assert_equal({ "actions" => Github::WRITE }, Github::NEEDS.fetch("clear_actions_cache"))
        end

        private

        def text_of(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end
    end
  end
end
