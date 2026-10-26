require "test_helper"

# What each code host answers Integrations::ReviewHost: the pull request, its files and links to them, and the head in
# the review's sandbox, which every host reads the same way (CodeHost::Code).
module Integrations
  module Packs
    class ReviewHostReadsTest < ActiveSupport::TestCase
      HEAD = "c4e4267d46e638ac6f257d117ab448c280d01c0b".freeze
      BASE = "b586e23aa0e1f6c7c2f2b0c3d4e5f60718293a4b".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
      end

      test "GitHub reads a pull request from a fork with its base, head and state, and a merged one with when it merged" do
        github, row = github_pack
        GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412", token: "ghs_token").returns(
          "title" => "Retry checkout", "body" => "Why", "user" => { "login" => "ada" }, "html_url" => "https://github.com/acme/checkout/pull/412",
          "state" => "open", "draft" => true, "merged_at" => nil, "base" => { "ref" => "main", "sha" => BASE },
          "head" => { "ref" => "retry", "sha" => HEAD, "repo" => { "full_name" => "ada/checkout" } }
        )

        pull = github.pull_request_for_review(row, repository: "acme/checkout", number: 412)

        assert_equal [ "Retry checkout", "ada", ReviewHost::STATE_OPEN, true, "main", BASE, "retry", HEAD ],
                     [ pull.title, pull.author, pull.state, pull.draft, pull.base_ref, pull.base_sha, pull.head_ref, pull.head_sha ]
        assert pull.fork?

        GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412", token: "ghs_token").returns(
          "title" => "t", "state" => "closed", "merged_at" => "2026-10-01T10:00:00Z", "base" => { "sha" => BASE }, "head" => { "sha" => HEAD }
        )
        merged = github.pull_request_for_review(row, repository: "acme/checkout", number: 412)
        assert_equal [ ReviewHost::STATE_MERGED, Time.iso8601("2026-10-01T10:00:00Z") ], [ merged.state, merged.merged_at ]
        assert_equal "acme/checkout", github.review_head_repository(pull), "GitHub keeps a fork's head in the base repository's pull request refs"
      end

      test "GitHub lists every file with its patch, refuses a list it cuts short, and links a file at a commit and line" do
        github, row = github_pack
        GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412/files?per_page=100&page=1", token: "ghs_token").returns([
          { "filename" => "app/a.rb", "status" => "modified", "additions" => 2, "deletions" => 1, "patch" => "@@ -1 +1 @@\n-a\n+b" },
          { "filename" => "app/new name.rb", "previous_filename" => "app/old.rb", "status" => "renamed", "additions" => 0, "deletions" => 0 }
        ])

        files = github.pull_request_files_for_review(row, repository: "acme/checkout", number: 412)

        assert_equal [ [ "app/a.rb", ReviewHost::STATUS_MODIFIED, "@@ -1 +1 @@\n-a\n+b" ], [ "app/new name.rb", ReviewHost::STATUS_RENAMED, nil ] ],
                     files.map { |file| [ file.path, file.status, file.patch ] }
        assert_equal "app/old.rb", files.last.previous_path
        assert_equal "https://github.com/acme/checkout/blob/#{HEAD}/app/new%20name.rb#L7",
                     github.pull_request_file_link(row, repository: "acme/checkout", sha: HEAD, path: "app/new name.rb", line: 7)

        full = Array.new(100) { |index| { "filename" => "f#{index}.rb", "status" => "added" } }
        (1..Github::FLAG_FILE_PAGES).each { |page| GithubApp.stubs(:get).with("/repos/acme/checkout/pulls/412/files?per_page=100&page=#{page}", token: "ghs_token").returns(full) }
        error = assert_raises(Integrations::Error) { github.pull_request_files_for_review(row, repository: "acme/checkout", number: 412) }
        assert_match "more files than GitHub lists", error.message
      end

      test "GitLab reads a merge request from a fork, its base where its branch left the target, and its files with too large ones left to the sandbox" do
        gitlab, row = gitlab_pack
        GitlabApi.any_instance.stubs(:get).with("/projects/acme%2Fweb/merge_requests/42").returns(
          "title" => "Add index", "description" => "d", "author" => { "username" => "ada" }, "web_url" => "https://gitlab.com/acme/web/-/merge_requests/42",
          "state" => "merged", "merged_at" => "2026-10-01T10:00:00Z", "target_branch" => "main", "source_branch" => "idx", "sha" => HEAD,
          "diff_refs" => { "base_sha" => BASE, "head_sha" => HEAD }, "source_project_id" => 9, "target_project_id" => 1
        )
        GitlabApi.any_instance.stubs(:get).with("/projects/9").returns("path_with_namespace" => "ada/web")

        pull = gitlab.pull_request_for_review(row, repository: "acme/web", number: 42)

        assert_equal [ ReviewHost::STATE_MERGED, BASE, HEAD, "ada/web" ], [ pull.state, pull.base_sha, pull.head_sha, pull.head_repository ]
        assert_equal "acme/web", gitlab.review_head_repository(pull)

        GitlabApi.any_instance.stubs(:get).with("/projects/9").raises(GitlabApi::NotFound, "404 Project Not Found")
        unreadable = gitlab.pull_request_for_review(row, repository: "acme/web", number: 42)
        assert_equal [ HEAD, "project 9" ], [ unreadable.head_sha, unreadable.head_repository ], "a fork this token cannot read still reads as a fork"
        assert unreadable.fork?

        GitlabApi.any_instance.stubs(:list).with("/projects/acme%2Fweb/merge_requests/42/diffs", {}, pages: Gitlab::FLAG_FILE_PAGES).returns([ [
          { "new_path" => "db/migrate/1.rb", "old_path" => "db/migrate/1.rb", "new_file" => true, "diff" => "@@ -0,0 +1 @@\n+x\n" },
          { "new_path" => "big.sql", "old_path" => "big.sql", "diff" => "", "too_large" => true },
          { "new_path" => "b.rb", "old_path" => "a.rb", "renamed_file" => true, "diff" => "" }
        ], false ])
        files = gitlab.pull_request_files_for_review(row, repository: "acme/web", number: 42)

        assert_equal [ [ ReviewHost::STATUS_ADDED, 1, "@@ -0,0 +1 @@\n+x\n" ], [ ReviewHost::STATUS_MODIFIED, 0, nil ], [ ReviewHost::STATUS_RENAMED, 0, nil ] ],
                     files.map { |file| [ file.status, file.additions, file.patch ] }
        assert_equal "a.rb", files.last.previous_path
        assert_equal "https://gitlab.com/acme/web/-/blob/#{HEAD}/db/migrate/1.rb#L3", gitlab.pull_request_file_link(row, repository: "acme/web", sha: HEAD, path: "db/migrate/1.rb", line: 3)
      end

      test "Bitbucket reads its short hashes back whole, reads a fork's head from the fork, and takes patches from a diff it sends whole" do
        bitbucket, row = bitbucket_pack
        BitbucketApi.any_instance.stubs(:get).with("/repositories/acme/web/pullrequests/42").returns(
          "title" => "Fix", "description" => "d", "author" => { "display_name" => "Ada" }, "links" => { "html" => { "href" => "https://bitbucket.org/acme/web/pull-requests/42" } },
          "state" => "OPEN", "source" => { "branch" => { "name" => "fix" }, "commit" => { "hash" => HEAD[0, 12] }, "repository" => { "full_name" => "ada/web" } },
          "destination" => { "branch" => { "name" => "main" }, "commit" => { "hash" => BASE[0, 12] }, "repository" => { "full_name" => "acme/web" } }
        )
        BitbucketApi.any_instance.stubs(:get).with("/repositories/ada/web/commits/#{HEAD[0, 12]}", "pagelen" => 1).returns("values" => [ { "hash" => HEAD } ])
        BitbucketApi.any_instance.stubs(:get).with("/repositories/acme/web/commits/#{BASE[0, 12]}", "pagelen" => 1).returns("values" => [ { "hash" => BASE } ])

        pull = bitbucket.pull_request_for_review(row, repository: "acme/web", number: 42)

        assert_equal [ HEAD, BASE, ReviewHost::STATE_OPEN ], [ pull.head_sha, pull.base_sha, pull.state ]
        assert_equal "ada/web", bitbucket.review_head_repository(pull)

        BitbucketApi.any_instance.stubs(:list).with("/repositories/acme/web/pullrequests/42/diffstat", {}, pages: Bitbucket::FLAG_FILE_PAGES).returns([ [
          { "status" => "modified", "lines_added" => 1, "lines_removed" => 1, "new" => { "path" => "app/a.rb" }, "old" => { "path" => "app/a.rb" } }
        ], false ])
        BitbucketApi.any_instance.stubs(:text).with("/repositories/acme/web/pullrequests/42/diff")
                    .returns("diff --git a/app/a.rb b/app/a.rb\n--- a/app/a.rb\n+++ b/app/a.rb\n@@ -1 +1 @@\n-a\n+b\n")
        file = bitbucket.pull_request_files_for_review(row, repository: "acme/web", number: 42).sole

        assert_equal [ "app/a.rb", ReviewHost::STATUS_MODIFIED, "@@ -1 +1 @@\n-a\n+b\n" ], [ file.path, file.status, file.patch ]
        assert_equal "https://bitbucket.org/acme/web/src/#{HEAD}/app/a.rb#lines-4", bitbucket.pull_request_file_link(row, repository: "acme/web", sha: HEAD, path: "app/a.rb", line: 4)
      end

      test "the head is checked out in the review's sandbox with every path at it, and a commit is compared with where its branch left the base" do
        github, row = github_pack(box_key: "pr-review-1")
        pull = ReviewHost::PullRequest.new(repository: "acme/checkout", number: 412, title: "t", url: nil, state: ReviewHost::STATE_OPEN, base_ref: "main",
                                           base_sha: BASE, head_ref: "x", head_sha: HEAD)
        CodeReading.any_instance.expects(:exec).with("acme/checkout", ref: HEAD, where: Sandboxes::Client::IN_GIT,
                                                                      argv: [ "-c", "core.quotePath=false", "ls-tree", "-r", "--name-only", Sandboxes::Client::COMMIT ])
                   .returns("stdout" => "app/a.rb\napp/b c.rb\n", "exit_code" => 0, "commit" => HEAD)

        checkout = github.pull_request_checkout(row, pull: pull)

        assert_equal [ "acme/checkout", HEAD, [ "app/a.rb", "app/b c.rb" ] ], [ checkout.repository, checkout.ref, checkout.paths ]

        CodeReading.any_instance.expects(:exec).with("acme/checkout", ref: HEAD, where: Sandboxes::Client::IN_GIT, argv: [
          "-c", "core.quotePath=false", "diff", "--merge-base", "--find-renames", "--no-color", "--no-ext-diff", BASE, Sandboxes::Client::COMMIT, "--", "app/a.rb"
        ]).returns("stdout" => "diff --git a/app/a.rb b/app/a.rb\n--- a/app/a.rb\n+++ b/app/a.rb\n@@ -1 +1 @@\n-a\n+b\n", "exit_code" => 0, "commit" => HEAD)

        assert_equal [ "app/a.rb" ], github.pull_request_sandbox_files(row, checkout: checkout, base_sha: BASE, path: "app/a.rb").map(&:path)
        assert_raises(Integrations::Error) { github.pull_request_sandbox_files(row, checkout: checkout, base_sha: "--output=/tmp/x") }
      end

      test "a sandbox that cannot start says so in the review's words" do
        github, row = github_pack(box_key: "pr-review-1")
        pull = ReviewHost::PullRequest.new(repository: "acme/checkout", number: 1, title: "t", url: nil, state: ReviewHost::STATE_OPEN, base_ref: "m",
                                           base_sha: BASE, head_ref: "x", head_sha: HEAD)
        CodeReading.any_instance.stubs(:exec).raises(Sandboxes::Error, "box gone")

        error = assert_raises(Integrations::Error) { github.pull_request_checkout(row, pull: pull) }
        assert_match "could not check out #{HEAD[0, 12]} from acme/checkout: box gone", error.message
      end

      private

      def github_pack(box_key: nil)
        integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
        row = integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
        GithubApp.stubs(:installation_token).returns("ghs_token")
        [ Github.new(integration, box_key: box_key), row ]
      end

      def gitlab_pack
        integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "gitlab", name: "GitLab")
        row = integration.integration_environments.create!
        Gitlab.store_credentials!(row, Gitlab::TOKEN => "glpat-token")
        [ Gitlab.new(integration), row ]
      end

      def bitbucket_pack
        integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "bitbucket", name: "Bitbucket")
        row = integration.integration_environments.create!
        row.store_fields!(Bitbucket::WORKSPACE => "acme")
        Bitbucket.store_credentials!(row, Bitbucket::TOKEN => "bb-token")
        [ Bitbucket.new(integration), row ]
      end
    end
  end
end
