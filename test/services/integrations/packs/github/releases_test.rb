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

        test "releases are changed and published as changes, each needing Contents write" do
          tools = Github.tool_definitions.index_by(&:name)
          %w[update_release publish_release].each do |name|
            assert_not tools.fetch(name).read_only, "#{name} changes GitHub"
            assert_equal({ "contents" => Github::WRITE }, Github::NEEDS.fetch(name))
          end
          assert_includes tools.fetch("publish_release").description, "builds and deploys nothing itself"
        end

        test "a placeholder in a draft's notes is filled in, found by its tag among the drafts" do
          draft = release("v2.4.1").merge("id" => 77, "draft" => true, "published_at" => nil, "body" => "## Changes\nRELEASE_NOTES\n\nThanks")
          GithubApp.expects(:get).with("/repos/acme/web/releases?per_page=100&page=1", token: "ghs_token").returns([ release("v2.4.0").merge("id" => 76), draft ])
          GithubApp.expects(:write).with(:patch, "/repos/acme/web/releases/77", { body: "## Changes\nBound retries\n\nThanks" }, token: "ghs_token")
                   .returns(draft.merge("body" => "## Changes\nBound retries\n\nThanks"))

          text = text_of(@pack.update_release(environment_row: @row, arguments: { "repo" => "acme/web", "tag" => "v2.4.1", "replace" => "RELEASE_NOTES", "with" => "Bound retries" }))

          assert text.start_with?("Changed the notes of release Spring in acme/web, which is still a draft.")
          assert_includes text, "## Changes\nBound retries"
        end

        test "a release's title, notes and prerelease flag are changed by its id" do
          GithubApp.expects(:get).with("/repos/acme/web/releases/76", token: "ghs_token").returns(release("v2.4.0").merge("id" => 76))
          GithubApp.expects(:write).with(:patch, "/repos/acme/web/releases/76", { name: "Autumn", prerelease: false, body: "Fixes checkout" }, token: "ghs_token")
                   .returns(release("v2.4.0").merge("name" => "Autumn", "body" => "Fixes checkout"))

          text = text_of(@pack.update_release(environment_row: @row, arguments: { "repo" => "acme/web", "id" => 76, "name" => "Autumn", "body" => "Fixes checkout", "prerelease" => false }))

          assert text.start_with?("Changed the notes, title, and prerelease flag of release Autumn in acme/web, which is published.")
        end

        test "an edit that names nothing to change, or a placeholder the notes lack, changes nothing" do
          GithubApp.expects(:write).never
          assert_match "Give body, replace and with, name or prerelease to change.",
                       assert_raises(NativePack::Error) { @pack.update_release(environment_row: @row, arguments: { "repo" => "acme/web", "tag" => "v2.4.0" }) }.message
          assert_match "Give body or replace, not both.",
                       assert_raises(NativePack::Error) { @pack.update_release(environment_row: @row, arguments: { "repo" => "acme/web", "tag" => "v2.4.0", "body" => "a", "replace" => "b", "with" => "c" }) }.message

          GithubApp.stubs(:get).with("/repos/acme/web/releases/76", token: "ghs_token").returns(release("v2.4.0").merge("id" => 76))
          error = assert_raises(NativePack::Error) { @pack.update_release(environment_row: @row, arguments: { "repo" => "acme/web", "id" => 76, "replace" => "TODO", "with" => "x" }) }
          assert_match "The notes of the release Spring do not contain \"TODO\", so nothing was changed.", error.message
        end

        test "a draft is published, marked latest unless asked not to, and answered with its page" do
          draft = release("v2.4.1").merge("id" => 77, "draft" => true, "published_at" => nil)
          GithubApp.expects(:get).with("/repos/acme/web/releases?per_page=100&page=1", token: "ghs_token").returns([ draft ])
          GithubApp.expects(:write).with(:patch, "/repos/acme/web/releases/77", { draft: false }, token: "ghs_token").returns(release("v2.4.1"))

          text = text_of(@pack.publish_release(environment_row: @row, arguments: { "repo" => "acme/web", "tag" => "v2.4.1" }))
          assert_includes text, "Published the release Spring for tag v2.4.1 on main in acme/web. It is marked the latest release, and its notes are public."
          assert text.end_with?("https://github.com/acme/web/releases/tag/v2.4.1")

          GithubApp.expects(:get).with("/repos/acme/web/releases/77", token: "ghs_token").returns(draft)
          GithubApp.expects(:write).with(:patch, "/repos/acme/web/releases/77", { draft: false, make_latest: "false" }, token: "ghs_token").returns(release("v2.4.1"))
          assert_includes text_of(@pack.publish_release(environment_row: @row, arguments: { "repo" => "acme/web", "id" => 77, "make_latest" => false })),
                          "It is not marked the latest release"
        end

        test "a release already published is refused, and so is a tag two drafts share or none has" do
          GithubApp.expects(:write).never
          GithubApp.stubs(:get).with("/repos/acme/web/releases/76", token: "ghs_token").returns(release("v2.4.0").merge("id" => 76))
          error = assert_raises(PolicyRefusal) { @pack.publish_release(environment_row: @row, arguments: { "repo" => "acme/web", "id" => 76 }) }
          assert_equal "The release Spring in acme/web was already published at 2026-09-01T10:00:00Z, so it is not published again.", error.message

          drafts = [ 1, 2 ].map { |id| release("v2.5.0").merge("id" => id, "draft" => true) }
          GithubApp.stubs(:get).with("/repos/acme/web/releases?per_page=100&page=1", token: "ghs_token").returns(drafts)
          error = assert_raises(PolicyRefusal) { @pack.publish_release(environment_row: @row, arguments: { "repo" => "acme/web", "tag" => "v2.5.0" }) }
          assert_match "2 releases in acme/web have tag v2.5.0, id 1 (release Spring) and id 2 (release Spring). Give the id of the one meant.", error.message

          error = assert_raises(NativePack::Error) { @pack.publish_release(environment_row: @row, arguments: { "repo" => "acme/web", "tag" => "v9" }) }
          assert_match "GitHub has no release, draft or published, with tag v9 in acme/web. list_releases shows the releases it has.", error.message

          assert_match "Give the release's tag or its id.", assert_raises(NativePack::Error) { @pack.publish_release(environment_row: @row, arguments: { "repo" => "acme/web" }) }.message
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
