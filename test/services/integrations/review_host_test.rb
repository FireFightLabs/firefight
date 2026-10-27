require "test_helper"

module Integrations
  class ReviewHostTest < ActiveSupport::TestCase
    GIT_DIFF = <<~DIFF.freeze
      diff --git a/app/models/order.rb b/app/models/order.rb
      index 1111111..2222222 100644
      --- a/app/models/order.rb
      +++ b/app/models/order.rb
      @@ -10,3 +10,4 @@ class Order
         def total
      +    retry_charge
           items.sum(&:price)
         end
      diff --git a/db/migrate/2_add_index.rb b/db/migrate/2_add_index.rb
      new file mode 100644
      index 0000000..3333333
      --- /dev/null
      +++ b/db/migrate/2_add_index.rb
      @@ -0,0 +1,2 @@
      +class AddIndex
      +end
      diff --git a/old/name.rb b/new/name.rb
      similarity index 90%
      rename from old/name.rb
      rename to new/name.rb
      index 4444444..5555555 100644
      --- a/old/name.rb
      +++ b/new/name.rb
      @@ -1 +1 @@
      -a
      +b
      diff --git a/logo.png b/logo.png
      index 6666666..7777777 100644
      Binary files a/logo.png and b/logo.png differ
      diff --git a/gone.rb b/gone.rb
      deleted file mode 100644
      index 8888888..0000000
      --- a/gone.rb
      +++ /dev/null
      @@ -1,2 +0,0 @@
      -x
      -y
    DIFF

    setup do
      @workspace = workspaces(:slack_workspace_one)
      @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
      @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
      @checkout = ReviewHost::Checkout.new(repository: "acme/api", ref: "h" * 40, paths: [ "app/models/order.rb" ])
    end

    test "git's own diff is read into changed files with their status, counts, hunks and binary files" do
      files = ReviewHost.parse_git_diff(GIT_DIFF).index_by(&:path)

      assert_equal %w[app/models/order.rb db/migrate/2_add_index.rb new/name.rb logo.png gone.rb], files.keys
      assert_equal [ ReviewHost::STATUS_MODIFIED, 1, 0 ], files["app/models/order.rb"].then { |file| [ file.status, file.additions, file.deletions ] }
      assert files["app/models/order.rb"].patch.start_with?("@@ -10,3 +10,4 @@")
      assert_equal ReviewHost::STATUS_ADDED, files["db/migrate/2_add_index.rb"].status
      assert_equal [ ReviewHost::STATUS_RENAMED, "old/name.rb" ], [ files["new/name.rb"].status, files["new/name.rb"].previous_path ]
      assert files["logo.png"].binary
      assert_nil files["logo.png"].patch
      assert_equal [ ReviewHost::STATUS_REMOVED, 0, 2 ], files["gone.rb"].then { |file| [ file.status, file.additions, file.deletions ] }
    end

    test "a path that holds the separator itself is read whole when both names are the same" do
      file = ReviewHost.parse_git_diff("diff --git a/docs/a b/c.md b/docs/a b/c.md\n--- a/docs/a b/c.md\n+++ b/docs/a b/c.md\n@@ -1 +1 @@\n-old\n+new\n").sole

      assert_equal [ "docs/a b/c.md", nil, ReviewHost::STATUS_MODIFIED ], [ file.path, file.previous_path, file.status ]
    end

    test "a comment can sit on the lines inside a hunk of the new file, and a hunk that only removes holds none" do
      ranges = ReviewHost.commentable_lines("@@ -10,3 +10,4 @@ class Order\n x\n@@ -40 +41 @@\n-a\n+b\n@@ -60,2 +61,0 @@\n-c\n-d\n")

      assert_equal [ 10...14, 41...42 ], ranges
    end

    test "every changed file is read once: a host's patch as it is, the rest from the sandbox in one go, and what cannot be read is left out with why" do
      files = [
        ReviewHost::ChangedFile.new(path: "app/models/order.rb", status: ReviewHost::STATUS_MODIFIED, patch: "@@ -1 +1 @@\n-a\n+b\n"),
        ReviewHost::ChangedFile.new(path: "db/migrate/2_add_index.rb", status: ReviewHost::STATUS_ADDED),
        ReviewHost::ChangedFile.new(path: "config/credentials.yml.enc", status: ReviewHost::STATUS_MODIFIED, patch: "@@ -1 +1 @@\n-s\n+t\n"),
        ReviewHost::ChangedFile.new(path: "logo.png", status: ReviewHost::STATUS_MODIFIED, binary: true),
        ReviewHost::ChangedFile.new(path: "vendor/huge.js", status: ReviewHost::STATUS_MODIFIED)
      ]
      ReviewHost.expects(:sandbox_files).once.with(@row, @checkout, base_sha: "b" * 40, key: "pr-review-1").returns(ReviewHost.parse_git_diff(GIT_DIFF))

      diffs = ReviewHost.diffs(@row, files, checkout: @checkout, base_sha: "b" * 40, key: "pr-review-1").index_by(&:path)

      assert_equal "diff --git a/app/models/order.rb b/app/models/order.rb\n--- a/app/models/order.rb\n+++ b/app/models/order.rb\n@@ -1 +1 @@\n-a\n+b\n",
                   diffs["app/models/order.rb"].text
      assert_includes diffs["db/migrate/2_add_index.rb"].text, "new file\n--- /dev/null\n+++ b/db/migrate/2_add_index.rb\n@@ -0,0 +1,2 @@\n+class AddIndex"
      assert_equal ReviewHost::LEFT_OUT_SECRETS, diffs["config/credentials.yml.enc"].left_out
      assert_equal ReviewHost::LEFT_OUT_BINARY, diffs["logo.png"].left_out
      assert_equal ReviewHost::LEFT_OUT_UNREAD, diffs["vendor/huge.js"].left_out
    end

    test "a sandbox that cannot compare leaves the files it was asked for out, never the ones the host gave" do
      files = [
        ReviewHost::ChangedFile.new(path: "app/a.rb", status: ReviewHost::STATUS_MODIFIED, patch: "@@ -1 +1 @@\n-a\n+b\n"),
        ReviewHost::ChangedFile.new(path: "app/b.rb", status: ReviewHost::STATUS_MODIFIED)
      ]
      ReviewHost.stubs(:sandbox_files).raises(Integrations::Error, "no base")

      diffs = ReviewHost.diffs(@row, files, checkout: @checkout, base_sha: "b" * 40, key: "k")

      assert_equal [ true, false ], diffs.map(&:read?)
      assert_equal ReviewHost::LEFT_OUT_UNREAD, diffs.last.left_out
    end

    test "a connection reviews when its pack reads pull requests, and the one that holds a repository on the map is the one used" do
      assert ReviewHost.reviews?(@integration)
      assert_not ReviewHost.reviews?(Integration.new(provider: "linear"))

      PullRequests.stubs(:holds?).returns(false)
      assert_nil ReviewHost.row_for(@workspace, "acme/api")
      PullRequests.stubs(:holds?).with(@row, "acme/api").returns(true)
      assert_equal @row, ReviewHost.row_for(@workspace, "acme/api")
    end
  end
end
