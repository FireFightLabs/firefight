require "test_helper"

module Integrations
  module Packs
    class Github
      class ReleasesTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "releases and tags are listed with their pages" do
          GithubApp.expects(:get).with("/repos/acme/web/releases?per_page=20", token: "ghs_token").returns([ release("v2.4.0") ])
          text = text_of(@pack.list_releases(environment_row: @row, arguments: { "repo" => "acme/web" }))
          assert_includes text, "  v2.4.0  Spring  published 2026-09-01T10:00:00Z  by ada  on main  https://github.com/acme/web/releases/tag/v2.4.0"
          assert text.end_with?("https://github.com/acme/web/releases")

          GithubApp.expects(:get).with("/repos/acme/web/tags?per_page=5", token: "ghs_token").returns([ { "name" => "v2.4.0", "commit" => { "sha" => "a" * 40 } } ])
          assert_includes text_of(@pack.list_tags(environment_row: @row, arguments: { "repo" => "acme/web", "limit" => 5 })), "  v2.4.0  #{'a' * 12}"
        end

        test "a release is read by its tag, or the latest one, with its notes" do
          GithubApp.expects(:get).with("/repos/acme/web/releases/latest", token: "ghs_token").returns(release("v2.4.0"))
          text = text_of(@pack.release_lookup(environment_row: @row, arguments: { "repo" => "acme/web" }))
          assert_includes text, "Bound retries"
          assert text.end_with?("https://github.com/acme/web/releases/tag/v2.4.0")

          GithubApp.stubs(:get).with("/repos/acme/web/releases/tags/v9", token: "ghs_token").raises(GithubApp::NotFound, "GitHub: Not Found")
          assert_match "GitHub has no release tagged v9 in acme/web.", assert_raises(NativePack::Error) { @pack.release_lookup(environment_row: @row, arguments: { "repo" => "acme/web", "tag" => "v9" }) }.message
        end

        test "a release Firefight writes is always a draft" do
          GithubApp.expects(:write).with(:post, "/repos/acme/web/releases",
                                         { tag_name: "v2.4.1", target_commitish: "main", body: "Fixes checkout", draft: true, generate_release_notes: false }, token: "ghs_token")
                   .returns("name" => "", "target_commitish" => "main", "html_url" => "https://github.com/acme/web/releases/tag/untagged-1")

          result = @pack.create_draft_release(environment_row: @row, arguments: { "repo" => "acme/web", "tag" => "v2.4.1", "target" => "main", "body" => "Fixes checkout", "draft" => false })

          assert_includes text_of(result), "Wrote a draft release v2.4.1 for tag v2.4.1 on main in acme/web. Nobody outside the repository sees it"
          assert text_of(result).end_with?("https://github.com/acme/web/releases/tag/untagged-1")
        end

        private

        def release(tag)
          { "tag_name" => tag, "name" => "Spring", "draft" => false, "prerelease" => false, "published_at" => "2026-09-01T10:00:00Z", "author" => { "login" => "ada" },
            "target_commitish" => "main", "body" => "Bound retries", "assets" => [], "html_url" => "https://github.com/acme/web/releases/tag/#{tag}" }
        end

        def text_of(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end
    end
  end
end
