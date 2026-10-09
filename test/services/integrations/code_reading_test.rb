require "test_helper"

module Integrations
  class CodeReadingTest < ActiveSupport::TestCase
    class FakeProvider
      attr_reader :started, :stopped, :running

      def initialize(running: [])
        @started = []
        @stopped = []
        @running = running
      end

      def start(name:)
        @started << name
        Sandboxes::Box.new(ref: "box-#{@started.size}", address: "http://127.0.0.1:9", key: "k#{@started.size}")
      end

      def stop(ref) = @stopped << ref
    end

    setup do
      @workspace = workspaces(:slack_workspace_one)
      integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
      @row = integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
      GithubApp.stubs(:installation_token).returns("ghs_token")
      @provider = FakeProvider.new
      Sandboxes.stubs(:provider).returns(@provider)
      Sandboxes.stubs(:provider_key).returns(Sandboxes::PROVIDER_DOCKER)
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
      Sandboxes.stubs(:provider).returns(nil)

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

    private

    def reading(key)
      remote = CodeReading::Remote.new(root: "https://github.com", user: "x-access-token", token: -> { GithubApp.installation_token(@row) })
      CodeReading.new(key: key, workspace: @workspace, remote: remote)
    end
  end
end
