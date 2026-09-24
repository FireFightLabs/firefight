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

    test "without a provider the tool says code reading is not set up" do
      Sandboxes.stubs(:provider).returns(nil)

      error = assert_raises(Error) { reading("investigation-1").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT) }
      assert_equal CodeReading::NOT_SET_UP, error.message
    end

    test "a token never shows in a failed fetch" do
      CodeReading.any_instance.stubs(:remote_url).returns("/nowhere/at/all")

      error = assert_raises(Error) { reading("investigation-1").exec("acme/app", argv: [ "log" ], where: Sandboxes::Client::IN_GIT) }
      assert_no_match "ghs_token", error.message
      assert_no_match Base64.strict_encode64("x-access-token:ghs_token"), error.message
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

    private

    def reading(key) = CodeReading.new(key: key, workspace: @workspace, environment_row: @row)
  end
end
