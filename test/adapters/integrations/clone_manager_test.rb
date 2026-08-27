require "test_helper"

module Integrations
  class CloneManagerTest < ActiveSupport::TestCase
    fixtures :workspaces, :users, :workspace_memberships

    setup do
      GithubApp.stubs(:installation_token).returns("ghs_token")
      integration = Integration.create!(
        workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE,
        provider: "github", name: "GitHub"
      )
      @row = integration.integration_environments.create!(base_config: { "installation_id" => "1" })
      @workspace_id = workspaces(:slack_workspace_one).id.to_s
    end

    test "clones on first use and reuses the clone afterwards" do
      FixtureRepo.with_clone_env do
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
    end

    test "a stale clone fetches new commits from the remote" do
      FixtureRepo.with_clone_env do |fixture, clone_root|
        CloneManager.with_repo(environment_row: @row, repo: "acme/checkout") { }
        FixtureRepo.add_commit(fixture, "new_file.rb", "# fresh\n", "Add fresh file")

        age_fetch_record(clone_root, "acme__checkout")

        CloneManager.with_repo(environment_row: @row, repo: "acme/checkout") do |dir|
          assert dir.join("new_file.rb").exist?, "stale clone must fast-forward to the remote"
        end
      end
    end

    test "heavy recent use never suppresses fetching - freshness is about fetch time, not use time" do
      FixtureRepo.with_clone_env do |fixture, clone_root|
        CloneManager.with_repo(environment_row: @row, repo: "acme/checkout") { }
        FixtureRepo.add_commit(fixture, "hot_fix.rb", "# fix\n", "Hot fix")

        age_fetch_record(clone_root, "acme__checkout")
        FileUtils.touch(clone_root.join(@workspace_id, "acme__checkout.last_used"))

        CloneManager.with_repo(environment_row: @row, repo: "acme/checkout") do |dir|
          assert dir.join("hot_fix.rb").exist?,
                 "a freshly-used clone with an old fetch must still refresh"
        end
      end
    end

    test "bookkeeping files live next to the clone, never inside it" do
      FixtureRepo.with_clone_env do |_fixture, clone_root|
        CloneManager.with_repo(environment_row: @row, repo: "acme/checkout") do |dir|
          assert_not dir.join(".ff_last_used").exist?
          assert clone_root.join(@workspace_id, "acme__checkout.last_used").exist?
        end
      end
    end

    test "least recently used clones are evicted over the cap" do
      FixtureRepo.with_clone_env do |_fixture, clone_root|
        CloneManager.stubs(:clone_limit).returns(2)

        [ "acme/one", "acme/two", "acme/three" ].each_with_index do |repo, index|
          CloneManager.with_repo(environment_row: @row, repo: repo) { }
          marker = clone_root.join(@workspace_id, "#{repo.gsub('/', '__')}.last_used")
          FileUtils.touch(marker, mtime: (10 - index).minutes.ago.to_time)
        end

        CloneManager.with_repo(environment_row: @row, repo: "acme/four") { }

        remaining = Dir.children(clone_root.join(@workspace_id))
                       .reject { |name| name.end_with?(".lock", ".last_used") }
        assert_includes remaining, "acme__four"
        assert_not_includes remaining, "acme__one", "the least recently used clone is evicted first"
        assert_operator remaining.size, :<=, 2
      end
    end

    test "git failures surface as readable errors without auth material" do
      FixtureRepo.with_clone_env do |fixture|
        CloneManager.stubs(:remote_url).returns("#{fixture}-missing")

        error = assert_raises(CloneManager::Error) do
          CloneManager.with_repo(environment_row: @row, repo: "acme/broken") { }
        end
        assert_match(/git clone failed/, error.message)
        assert_no_match(/Basic [A-Za-z0-9+\/=]{8}/, error.message)
      end
    end

    private

    # Freshness is judged by FETCH_HEAD's mtime (or .git ctime for a clone
    # that never fetched). Writing an old FETCH_HEAD makes the clone stale.
    def age_fetch_record(clone_root, repo_dir_name)
      fetch_head = clone_root.join(@workspace_id, repo_dir_name, ".git/FETCH_HEAD")
      FileUtils.touch(fetch_head, mtime: 10.minutes.ago.to_time)
    end
  end
end
