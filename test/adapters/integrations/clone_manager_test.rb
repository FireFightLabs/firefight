require "test_helper"

module Integrations
  class CloneManagerTest < ActiveSupport::TestCase
    fixtures :workspaces, :users, :workspace_memberships

    setup do
      @fixture = FixtureRepo.create!
      @clone_root = Dir.mktmpdir("clone-root")
      CloneManager.stubs(:root).returns(Pathname.new(@clone_root))
      CloneManager.stubs(:remote_url).returns(@fixture)
      GithubApp.stubs(:installation_token).returns("ghs_token")

      integration = Integration.create!(
        workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE,
        provider: "github", name: "GitHub"
      )
      @row = integration.integration_environments.create!(base_config: { "installation_id" => "1" })
    end

    teardown do
      FileUtils.rm_rf(@fixture)
      FileUtils.rm_rf(@clone_root)
    end

    test "clones on first use and reuses the clone afterwards" do
      first_path = nil
      CloneManager.with_repo(environment_row: @row, repo: "acme/checkout") do |dir|
        first_path = dir
        assert dir.join(".git").directory?
        assert dir.join("payment.rb").exist?
      end

      CloneManager.expects(:clone!).never
      CloneManager.with_repo(environment_row: @row, repo: "acme/checkout") do |dir|
        assert_equal first_path, dir
      end
    end

    test "a stale clone fetches new commits from the remote" do
      CloneManager.with_repo(environment_row: @row, repo: "acme/checkout") { }
      FixtureRepo.add_commit(@fixture, "new_file.rb", "# fresh\n", "Add fresh file")

      marker = Pathname.new(@clone_root).join(workspaces(:slack_workspace_one).id.to_s,
                                              "acme__checkout", CloneManager::USED_MARKER)
      FileUtils.touch(marker, mtime: 10.minutes.ago.to_time)

      CloneManager.with_repo(environment_row: @row, repo: "acme/checkout") do |dir|
        assert dir.join("new_file.rb").exist?, "stale clone must fast-forward to the remote"
      end
    end

    test "least recently used clones are evicted over the cap" do
      CloneManager.stubs(:clone_limit).returns(2)

      [ "acme/one", "acme/two", "acme/three" ].each_with_index do |repo, index|
        CloneManager.with_repo(environment_row: @row, repo: repo) { }
        marker = Pathname.new(@clone_root).join(workspaces(:slack_workspace_one).id.to_s,
                                                repo.gsub("/", "__"), CloneManager::USED_MARKER)
        FileUtils.touch(marker, mtime: (10 - index).minutes.ago.to_time)
      end

      CloneManager.with_repo(environment_row: @row, repo: "acme/four") { }

      workspace_root = Pathname.new(@clone_root).join(workspaces(:slack_workspace_one).id.to_s)
      remaining = Dir.children(workspace_root).reject { |name| name.end_with?(".lock") }
      assert_includes remaining, "acme__four"
      assert_not_includes remaining, "acme__one", "the least recently used clone is evicted first"
      assert_operator remaining.size, :<=, 2
    end

    test "git failures surface as readable errors without auth material" do
      CloneManager.stubs(:remote_url).returns("#{@fixture}-missing")

      error = assert_raises(CloneManager::Error) do
        CloneManager.with_repo(environment_row: @row, repo: "acme/broken") { }
      end
      assert_match(/git clone failed/, error.message)
      assert_no_match(/Basic [A-Za-z0-9+\/=]{8}/, error.message)
    end
  end
end
