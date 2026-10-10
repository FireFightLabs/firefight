require "test_helper"

module Integrations
  class CodeReadingTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    class FakeProvider < Sandboxes::Provider
      attr_reader :started, :stopped, :running

      def initialize(running: [])
        @started = []
        @stopped = []
        @running = running
      end

      def start(name:, **)
        @started << name
        Sandboxes::Box.new(ref: "box-#{@started.size}", address: "http://127.0.0.1:9", key: "k#{@started.size}")
      end

      def stop(ref) = @stopped << ref

      def size = "2 CPU, 4g"
    end

    # A provider that keeps a box's disk itself, as boat.dev does.
    class KeepingProvider < FakeProvider
      attr_reader :kept, :discarded, :froms

      def initialize(...)
        super
        @kept = []
        @discarded = []
        @froms = []
      end

      def start(name:, from: nil, **)
        @froms << from
        super
      end

      def hourly_micros = 36_000

      def keeps_copies? = true

      def keep(ref) = "kept-#{@kept.push(ref).size}"

      def kept_ready?(_name) = true

      def discard(name) = @discarded << name

      def tidy(kept_refs:) = @tidied = kept_refs

      def tidied = @tidied
    end

    setup do
      @workspace = workspaces(:slack_workspace_one)
      integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
      @row = integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
      GithubApp.stubs(:installation_token).returns("ghs_token")
      @provider = FakeProvider.new
      Sandboxes.stubs(:provider).returns(@provider)
      SandboxProviders.stubs(:order_for).returns([ SandboxProviders::DOCKER ])
      SandboxProviders.stubs(:in_use).returns([ SandboxProviders::DOCKER ])
      Sandboxes::Client.any_instance.stubs(:wait_until_ready!)
      @fixture = FixtureRepo.create!
      CodeReading.any_instance.stubs(:remote_url).returns(@fixture)
      @pushed = []
      Sandboxes::Client.any_instance.stubs(:push).with { |name, bundle| @pushed << [ name, bundle ] }.returns("head" => "abc", "default_branch" => "main")
      Sandboxes::Client.any_instance.stubs(:exec).returns("stdout" => "ok", "commit" => "abc")
    end

    teardown { FileUtils.rm_rf(@fixture) }

    test "a run's first read starts one box and hands it the repository with its history, and later reads reuse both" do
      reading("investigation-1").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)
      reading("investigation-1").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)

      assert_equal 1, @provider.started.size
      assert_equal 1, @pushed.size
      name, bundle = @pushed.sole
      assert_equal "acme__app", name
      assert bundle.start_with?("# v2 git bundle"), "the whole history travels as a git bundle"
      box = CodeBox.live.find_by!(key: "investigation-1")
      assert_equal "abc", box.repositories.dig("acme/app", "head")
      assert_equal "k1", box.secret
    end

    test "a box is started for its workspace and run, so a box the app loses its row for can still be told whose it is" do
      @provider.expects(:start).with { |owner:, **| owner == Sandboxes::Owner.new(workspace_id: @workspace.id, key: "investigation-owned") }
               .returns(Sandboxes::Box.new(ref: "box-1", address: "http://127.0.0.1:9", key: "k1"))

      reading("investigation-owned").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)
    end

    test "two runs read in two boxes" do
      reading("investigation-1").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)
      reading("conversation-2").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)

      assert_equal 2, @provider.started.size
    end

    test "a commit the box does not know sends the repository again once, for a push made since" do
      reading("investigation-1").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)
      CodeBox.live.find_by!(key: "investigation-1").update_columns(repositories: { "acme/app" => { "pushed_at" => 1.hour.ago.iso8601 } })
      Sandboxes::Client.any_instance.stubs(:exec).raises(Sandboxes::Error, "acme__app has no commit f00").then.returns("stdout" => "found", "commit" => "f00")

      result = reading("investigation-1").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT, ref: "f00")

      assert_equal "found", result["stdout"]
      assert_equal 2, @pushed.size
    end

    test "a branch's newest head the box was handed the repository before is fetched again, so a change is written on it" do
      reading("conversation-1").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)
      CodeBox.live.find_by!(key: "conversation-1").update_columns(repositories: { "acme/app" => { "pushed_at" => 10.minutes.ago.iso8601 } })
      asked = []
      Sandboxes::Client.any_instance.stubs(:prepare).with { |**given| asked << given }.raises(Sandboxes::Error, "acme__app has no commit c6ce34be")
                       .then.returns("commit" => "c6ce34be")

      reading("conversation-1").prepare("acme/app", ref: "c6ce34be")

      assert_equal 2, @pushed.size, "the repository was sent again with the commit merged since"
      assert_equal "c6ce34be", asked.last[:ref]
    end

    test "without a provider the tool says code reading is not set up, and that it will not start working mid run" do
      SandboxProviders.stubs(:order_for).returns([])

      error = assert_raises(Unavailable) { reading("investigation-no-provider").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT) }
      assert_match CodeReading::NOT_SET_UP, error.message
      assert_match "do not call them again", error.message
    end

    test "a box that cannot start is reported once, and later reads in the run fail at once without trying again" do
      @provider.expects(:start).once.raises(Sandboxes::Error, "SANDBOX_PROVIDER is docker, but the Docker daemon at /var/run/docker.sock cannot be reached (EACCES).")

      first = assert_raises(Unavailable) { reading("investigation-cannot-start").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT) }
      second = assert_raises(Unavailable) { reading("investigation-cannot-start").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT) }

      assert_match "cannot be reached (EACCES)", first.message
      assert_equal first.message, second.message
    end

    test "a box that is gone, stopped outside Firefight, is replaced once and the read runs in the new one" do
      reading("investigation-lost").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)
      Sandboxes::Client.any_instance.stubs(:exec).raises(Sandboxes::Error, "could not reach 127.0.0.1 (Errno::ECONNREFUSED)")
                                              .then.returns("stdout" => "found", "commit" => "abc")
      Sandboxes::Client.any_instance.stubs(:alive?).returns(false)

      result = reading("investigation-lost").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)

      assert_equal "found", result["stdout"]
      assert_equal 2, @provider.started.size
      assert_equal [ "box-1" ], @provider.stopped
      assert_equal "box-2", CodeBox.live.find_by!(key: "investigation-lost").box_ref
      assert_equal 2, @pushed.size, "the new box is handed the repository again"
    end

    test "a command that fails in a box that still answers is reported, and the box is kept" do
      reading("investigation-alive").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)
      Sandboxes::Client.any_instance.stubs(:exec).raises(Sandboxes::Error, "grep: bad regex")
      Sandboxes::Client.any_instance.stubs(:alive?).returns(true)

      assert_raises(Sandboxes::Error) { reading("investigation-alive").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT) }
      assert_equal 1, @provider.started.size
    end

    test "a token never shows in a failed fetch" do
      CodeReading.any_instance.stubs(:remote_url).returns("/nowhere/at/all")

      error = assert_raises(Error) { reading("investigation-1").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT) }
      assert_no_match "ghs_token", error.message
      assert_no_match Base64.strict_encode64("x-access-token:ghs_token"), error.message
    end

    test "a repository on another code host is its own repository in the box, under a name the box can keep" do
      remote = CodeReading::Remote.new(root: "https://gitlab.example.com", user: "oauth2", token: -> { "glpat_token" }, host: "gitlab.example.com",
                                       options: [ "http.extraHeader=X-Firefight: 1" ])

      CodeReading.new(key: "investigation-1", workspace: @workspace, remote: remote).exec("group/sub/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)

      assert_equal "gitlab.example.com:group/sub/app", remote.key("group/sub/app")
      assert_match(/\Agitlab.example.com__group.sub.app-[0-9a-f]{10}\z/, @pushed.sole.first)
      assert CodeBox.live.find_by!(key: "investigation-1").holds?("gitlab.example.com:group/sub/app")
      assert_equal "acme__app", CodeReading::Remote.new(root: "https://github.com", user: "x", token: -> { "t" }).stored_name("acme/app")
    end

    test "closing a run's box stops it once, however many times it is asked" do
      reading("investigation-1").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)

      CodeReading.close("investigation-1")
      CodeReading.close("investigation-1")

      assert_equal [ "box-1" ], @provider.stopped
      assert_not CodeBox.live.exists?(key: "investigation-1")
    end

    test "a chat's box is let go only once it has sat idle" do
      reading("conversation-2").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)

      CodeReading.close_idle("conversation-2")
      assert_empty @provider.stopped

      CodeBox.live.find_by!(key: "conversation-2").update_columns(last_used_at: (CodeBox::IDLE_AFTER + 1.minute).ago)
      CodeReading.close_idle("conversation-2")
      assert_equal [ "box-1" ], @provider.stopped
    end

    test "the sweep stops abandoned boxes and boxes nothing knows, but not one still being started" do
      reading("investigation-1").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)
      CodeBox.live.find_by!(key: "investigation-1").update_columns(last_used_at: 2.hours.ago)
      @provider.running.push(
        Sandboxes::Running.new(ref: "orphan", started_at: 1.hour.ago),
        Sandboxes::Running.new(ref: "starting", started_at: 1.minute.ago)
      )

      CodeReading.sweep!

      assert_equal [ "box-1", "orphan" ], @provider.stopped
    end

    test "a box remembered as unavailable is forgotten once its time passes, so a long-lived worker keeps none for old runs" do
      CodeReading.unavailable!("run-old", "The sandbox did not start.")
      assert_equal "The sandbox did not start.", CodeReading.unavailable("run-old")

      travel CodeReading::UNAVAILABLE_FOR + 1.second do
        CodeReading.unavailable!("run-new", "The sandbox did not start.")

        remembered = CodeReading.send(:unavailable_by_key)
        assert_not remembered.key?("run-old")
        assert_nil CodeReading.unavailable("run-new-other")
      end
      CodeReading.send(:unavailable_by_key).delete("run-new")
    end

    test "a copy installed from nothing is kept for the workspace, and a later box with the same lockfiles and setup starts from it" do
      setup = { "services" => [], "env" => { "RAILS_ENV" => "test" }, "commands" => [ "bin/setup" ] }
      stub_preparing(lock_digest: "locks-1")
      Sandboxes::Client.any_instance.stubs(:prepare).returns("already" => false, "restored" => false,
                                                             "prepared" => [ { "exit_code" => 0 } ], "setup" => [ { "exit_code" => 0 } ])
      Sandboxes::Client.any_instance.expects(:upload_archive).never
      Sandboxes::Client.any_instance.expects(:download_archive).with { |path:, **| File.write(path, "installed") }.returns(true)

      reading("investigation-1").prepare("acme/app", ref: "abc", setup: setup)

      kept = PreparedCopy.find_by!(workspace: @workspace, repository: "acme/app")
      assert_equal PreparedCopy.key_for(lock_digest: "locks-1", setup_digest: Digest::SHA256.hexdigest(JSON.generate(setup))), kept.install_key

      uploaded = []
      Sandboxes::Client.any_instance.stubs(:upload_archive).with { |repository:, ref:, path:| uploaded << [ repository, ref, File.read(path) ] }.returns("restored" => true)
      Sandboxes::Client.any_instance.stubs(:prepare).returns("already" => false, "restored" => true, "prepared" => [], "setup" => [])
      Sandboxes::Client.any_instance.expects(:download_archive).never

      travel 1.day do
        reading("investigation-2").prepare("acme/app", ref: "def", setup: setup)
        assert_equal Time.current.to_i, kept.reload.last_used_at.to_i
      end

      assert_equal [ [ "acme__app", "def", "installed" ] ], uploaded
    end

    test "what one workspace installed never reaches another's box, and another setup installs again" do
      PreparedCopy.keep!(workspaces(:slack_workspace_two), "acme/app", PreparedCopy.key_for(lock_digest: "locks-1", setup_digest: nil), archive_file)
      PreparedCopy.keep!(@workspace, "acme/app", PreparedCopy.key_for(lock_digest: "locks-1", setup_digest: "another"), archive_file)
      stub_preparing(lock_digest: "locks-1")
      Sandboxes::Client.any_instance.stubs(:prepare).returns("already" => false, "prepared" => [ { "exit_code" => 1 } ])
      Sandboxes::Client.any_instance.expects(:upload_archive).never
      Sandboxes::Client.any_instance.expects(:download_archive).never

      reading("investigation-1").prepare("acme/app", ref: "abc")
    end

    test "a box from an image before setups prepares as it always did" do
      Sandboxes::Client.any_instance.stubs(:setups?).returns(false)
      Sandboxes::Client.any_instance.expects(:prepare_state).never
      Sandboxes::Client.any_instance.expects(:prepare).with(repository: "acme__app", ref: "abc").returns("already" => false, "prepared" => [])

      reading("investigation-1").prepare("acme/app", ref: "abc", setup: { "commands" => [ "bin/setup" ] })
    end

    test "a provider that cannot start a box hands over to the backup, and the box remembers who refused it and why" do
      backup = FakeProvider.new
      SandboxProviders.stubs(:order_for).returns([ SandboxProviders::BOAT, SandboxProviders::NORTHFLANK ])
      Sandboxes.stubs(:provider).with(SandboxProviders::BOAT).returns(@provider)
      Sandboxes.stubs(:provider).with(SandboxProviders::NORTHFLANK).returns(backup)
      @provider.expects(:start).with { |fail_fast:, **| fail_fast }.raises(Sandboxes::Error, "boat.dev answered 503: No machine of this type is ready. (no_ready_machine)")

      reading("investigation-failover").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)

      box = CodeBox.live.find_by!(key: "investigation-failover")
      assert_equal SandboxProviders::NORTHFLANK, box.provider
      assert_equal SandboxProviders::BOAT, box.failed_over_from
      assert_equal "boat.dev answered 503: No machine of this type is ready. (no_ready_machine)", box.failover_reason
      assert_equal 1, backup.started.size
    end

    test "a workspace held to a provider that is down never fails over to the deployment's backup, and the run is told why" do
      SandboxProviders.unstub(:order_for)
      ENV.stubs(:[]).with(anything).returns(nil)
      ENV.stubs(:[]).with("SANDBOX_PROVIDER").returns(SandboxProviders::BOAT)
      ENV.stubs(:[]).with("SANDBOX_BACKUP_PROVIDER").returns(SandboxProviders::NORTHFLANK)
      @workspace.update!(sandbox_provider: SandboxProviders::BOAT)
      backup = FakeProvider.new
      Sandboxes.stubs(:provider).with(SandboxProviders::BOAT).returns(@provider)
      Sandboxes.stubs(:provider).with(SandboxProviders::NORTHFLANK).returns(backup)
      @provider.expects(:start).once.with { |fail_fast:, **| !fail_fast }.raises(Sandboxes::Error, "boat.dev answered 502: Bad gateway.")

      first = assert_raises(Unavailable) { reading("investigation-held").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT) }
      again = assert_raises(Unavailable) { reading("investigation-held").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT) }

      assert_match "Code reading cannot run right now: boat.dev answered 502: Bad gateway.", first.message
      assert_equal first.message, again.message, "later reads in the run fail at once, without asking boat.dev again"
      assert_empty backup.started, "the backup is never tried for a held workspace"
      assert_not CodeBox.exists?(key: "investigation-held")
    end

    test "when every provider refuses, the run is told each one's reason once" do
      SandboxProviders.stubs(:order_for).returns([ SandboxProviders::BOAT, SandboxProviders::NORTHFLANK ])
      @provider.stubs(:start).raises(Sandboxes::Error, "refused.")

      error = assert_raises(Unavailable) { reading("investigation-nowhere").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT) }

      assert_match "boat.dev: refused. Northflank: refused.", error.message
      assert_not CodeBox.exists?(key: "investigation-nowhere")
    end

    test "a box records its size, its price and how long it ran, for its cost" do
      keeping = KeepingProvider.new
      Sandboxes.stubs(:provider).returns(keeping)
      reading("investigation-cost").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)
      box = CodeBox.live.find_by!(key: "investigation-cost")
      assert_equal [ "2 CPU, 4g", 36_000 ], [ box.size, box.hourly_micros ]

      travel 30.minutes do
        CodeReading.close("investigation-cost")
      end

      assert_in_delta 1_800, box.reload.running_seconds, 2
    end

    test "with a provider that keeps disks, a prepared copy is kept there, and a later run's box starts from it" do
      keeping = KeepingProvider.new
      Sandboxes.stubs(:provider).returns(keeping)
      stub_preparing(lock_digest: "locks-1")
      Sandboxes::Client.any_instance.stubs(:prepare).returns("already" => false, "restored" => false, "commit" => "abc",
                                                             "prepared" => [ { "exit_code" => 0 } ], "setup" => [])
      Sandboxes::Client.any_instance.expects(:download_archive).never

      reading("investigation-1").prepare("acme/app", ref: "abc")

      kept = PreparedCopy.find_by!(workspace: @workspace, repository: "acme/app")
      assert_equal [ SandboxProviders::DOCKER, "kept-1", "abc" ], [ kept.kept_in, kept.kept_ref, kept.commit ]
      assert_equal [ "box-1" ], keeping.kept

      seeded = []
      Sandboxes::Client.any_instance.stubs(:seed).with { |**given| seeded << given }.returns("restored" => true)
      Sandboxes::Client.any_instance.stubs(:prepare).returns("already" => false, "restored" => true, "prepared" => [], "setup" => [])
      Sandboxes::Client.any_instance.expects(:upload_archive).never

      assert_enqueued_with(job: CodeBoxRetireJob, args: [ SandboxProviders::DOCKER, "box-2" ]) do
        reading("investigation-2").prepare("acme/app", ref: "def")
      end

      box = CodeBox.live.find_by!(key: "investigation-2")
      assert_equal [ nil, nil, "kept-1" ], keeping.froms
      assert_equal "box-3", box.box_ref, "the run moved to the box started from the kept copy"
      assert_equal [ { repository: "acme__app", ref: "def", from: "abc" } ], seeded
      assert_equal 3, @pushed.size, "the repository is fetched into the kept copy for commits made since"
      assert_equal 1, keeping.kept.size, "a copy started from a kept one is not kept again"
    end

    test "a box already holding another repository keeps its work and installs from nothing" do
      keeping = KeepingProvider.new
      Sandboxes.stubs(:provider).returns(keeping)
      PreparedCopy.kept!(SandboxProviders::DOCKER, @workspace, "acme/app", PreparedCopy.key_for(lock_digest: "locks-1", setup_digest: nil),
                         kept_ref: "kept-old", commit: "abc")
      stub_preparing(lock_digest: "locks-1")
      Sandboxes::Client.any_instance.stubs(:prepare).returns("already" => false, "restored" => false, "prepared" => [ { "exit_code" => 1 } ])
      reading("investigation-1").exec("acme/other", argv: [ "log" ], where: Sandboxes::Client::IN_GIT)

      reading("investigation-1").prepare("acme/app", ref: "def")

      assert_equal [ nil ], keeping.froms
    end

    test "the sweep asks every provider in use, and lets go of what a provider keeps that nobody used" do
      keeping = KeepingProvider.new
      Sandboxes.stubs(:provider).returns(keeping)
      old = PreparedCopy.kept!(SandboxProviders::DOCKER, @workspace, "acme/app", "key-1", kept_ref: "kept-old", commit: "abc").first
      fresh = PreparedCopy.kept!(SandboxProviders::DOCKER, @workspace, "acme/web", "key-1", kept_ref: "kept-fresh", commit: "abc").first
      old.update_columns(last_used_at: (PreparedCopy::KEPT_UNUSED_FOR + 1.day).ago)

      CodeReading.sweep_prepared!
      CodeReading.sweep!

      assert_equal [ "kept-old" ], keeping.discarded
      assert_not PreparedCopy.exists?(old.id)
      assert_equal Set[fresh.kept_ref], keeping.tidied
    end

    private

    def stub_preparing(lock_digest:)
      Sandboxes::Client.any_instance.stubs(:setups?).returns(true)
      Sandboxes::Client.any_instance.stubs(:prepare_state).returns("lock_digest" => lock_digest, "prepared" => false)
    end

    def archive_file
      Tempfile.create("prepared").tap { |file| file.write("installed") && file.flush }.path
    end

    def reading(key)
      remote = CodeReading::Remote.new(root: "https://github.com", user: "x-access-token", token: -> { GithubApp.installation_token(@row) })
      CodeReading.new(key: key, workspace: @workspace, remote: remote)
    end
  end
end
