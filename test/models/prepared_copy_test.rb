require "test_helper"

class PreparedCopyTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @other = workspaces(:slack_workspace_two)
    @archive = Tempfile.new([ "prepared", ".tar.gz" ])
    @archive.write("installed")
    @archive.flush
  end

  teardown { @archive.close! }

  test "the key follows the lockfiles and the setup, so the same ones on another commit find what was kept" do
    same = PreparedCopy.key_for(lock_digest: "locks-1", setup_digest: "setup-1")

    assert_equal same, PreparedCopy.key_for(lock_digest: "locks-1", setup_digest: "setup-1")
    refute_equal same, PreparedCopy.key_for(lock_digest: "locks-2", setup_digest: "setup-1")
    refute_equal same, PreparedCopy.key_for(lock_digest: "locks-1", setup_digest: "setup-2")
    refute_equal same, PreparedCopy.key_for(lock_digest: "locks-1", setup_digest: nil)
  end

  test "a kept copy is found only by its own workspace, repository and key" do
    kept = PreparedCopy.keep!(@workspace, "acme/api", "key-1", @archive.path)

    assert_equal kept, PreparedCopy.usable(@workspace, "acme/api", "key-1")
    assert_equal "installed", kept.archive.download
    assert_nil PreparedCopy.usable(@other, "acme/api", "key-1"), "never another workspace's"
    assert_nil PreparedCopy.usable(@workspace, "acme/web", "key-1")
    assert_nil PreparedCopy.usable(@workspace, "acme/api", "key-2")
  end

  test "a second keep of the same key keeps the first, and a repository keeps only its newest few" do
    first = PreparedCopy.keep!(@workspace, "acme/api", "key-1", @archive.path)
    assert_nil PreparedCopy.keep!(@workspace, "acme/api", "key-1", @archive.path)

    travel 1.minute do
      (2..PreparedCopy::KEPT_PER_REPOSITORY).each { |number| PreparedCopy.keep!(@workspace, "acme/api", "key-#{number}", @archive.path) }
    end
    PreparedCopy.keep!(@other, "acme/api", "key-1", @archive.path)
    travel 2.minutes do
      PreparedCopy.keep!(@workspace, "acme/api", "key-new", @archive.path)
    end

    kept = PreparedCopy.where(workspace: @workspace, repository: "acme/api").pluck(:install_key)
    assert_equal PreparedCopy::KEPT_PER_REPOSITORY, kept.size
    refute PreparedCopy.exists?(first.id), "the oldest goes first"
    assert PreparedCopy.exists?(workspace: @other, repository: "acme/api"), "another workspace's are its own"
  end

  test "one nobody used for a week is removed with its archive, and one used since stays" do
    used = PreparedCopy.keep!(@workspace, "acme/api", "key-1", @archive.path)
    unused = PreparedCopy.keep!(@workspace, "acme/web", "key-1", @archive.path)

    travel PreparedCopy::KEPT_UNUSED_FOR + 1.day do
      used.used!
      PreparedCopySweepJob.perform_now
    end

    assert PreparedCopy.exists?(used.id)
    refute PreparedCopy.exists?(unused.id)
  end
end
