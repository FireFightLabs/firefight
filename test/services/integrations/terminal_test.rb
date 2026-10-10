require "test_helper"

module Integrations
  class TerminalTest < ActiveSupport::TestCase
    class FakeProvider < Sandboxes::Provider
      attr_reader :started, :stopped

      def initialize(region: nil)
        @started = []
        @stopped = []
        @region = region
      end

      def start(name:, **)
        @started << name
        Sandboxes::Box.new(ref: "box-#{@started.size}", address: "http://127.0.0.1:9", key: "k#{@started.size}")
      end

      def stop(ref) = @stopped << ref

      def region = @region
    end

    setup do
      @workspace = workspaces(:slack_workspace_one)
      @provider = FakeProvider.new(region: "europe-west")
      Sandboxes.stubs(:provider).returns(@provider)
      SandboxProviders.stubs(:order_for).returns([ SandboxProviders::DOCKER ])
      Sandboxes::Client.any_instance.stubs(:wait_until_ready!)
      Sandboxes::Client.any_instance.stubs(:terminal?).returns(true)
    end

    test "the terminal is offered where the workspace has a sandbox provider to try, and not otherwise" do
      assert Terminal.available?(@workspace)

      SandboxProviders.stubs(:order_for).with(@workspace).returns([])
      assert_not Terminal.available?(@workspace)
    end

    test "a run's first command starts its box, and later commands and files use the same one" do
      Sandboxes::Client.any_instance.expects(:terminal).twice.with { |argv:, env:, **| argv == [ "bash", "-c", "ls" ] && env == { "A" => "1" } }
                       .returns("stdout" => "x", "exit_code" => 0)
      Sandboxes::Client.any_instance.expects(:place_file).with("result_1.txt", "data").returns("path" => "/terminal/results/result_1.txt")

      terminal.run("ls", env: { "A" => "1" })
      assert_equal "/terminal/results/result_1.txt", terminal.place("result_1.txt", "data")
      terminal.run("ls", env: { "A" => "1" })

      assert_equal 1, @provider.started.size
      assert CodeBox.live.exists?(key: "conversation-9")
    end

    test "nothing starts a box until a command needs one" do
      Terminal.new(key: "conversation-9", workspace: @workspace)

      assert_empty @provider.started
    end

    test "a box that is gone is replaced once and the command runs in the new one" do
      calls = 0
      Sandboxes::Client.any_instance.stubs(:terminal).with do |**|
        calls += 1
        raise Sandboxes::Error, "connection refused" if calls == 1

        true
      end.returns("stdout" => "ok", "exit_code" => 0)
      Sandboxes::Client.any_instance.stubs(:alive?).returns(false)

      assert_equal "ok", terminal.run("ls")["stdout"]
      assert_equal 2, @provider.started.size
      assert_equal [ "box-1" ], @provider.stopped
    end

    test "a box from an image before the terminal says so, and is kept" do
      Sandboxes::Client.any_instance.stubs(:terminal?).returns(false)

      assert_equal CodeReading::OLD_IMAGE, assert_raises(Sandboxes::Error) { terminal.run("ls") }.message
      assert_empty @provider.stopped
    end

    test "an address is checked by an argument list, never a shell, from the region of the box it ran in" do
      Sandboxes::Client.any_instance.expects(:terminal).with(argv: [ "ruby", Terminal::OUTSIDE_CHECK, "https://x.dev/;rm -rf /", "GET" ], env: {},
                                                             timeout: Terminal::OUTSIDE_CHECK_TIMEOUT, on_output: nil)
                       .returns("stdout" => { "host" => "x.dev" }.to_json, "exit_code" => 0)

      checked = terminal.check("https://x.dev/;rm -rf /", method: "GET")

      assert_equal [ { "host" => "x.dev" }, "europe-west" ], [ checked.answer, checked.region ]
    end

    test "each provider says where its boxes run, boat in the EU, Docker where the deployment says, and none unnamed" do
      Sandboxes.unstub(:provider)
      assert_equal Sandboxes::Boat::REGION, Sandboxes::Boat.new(api: stub).region

      given = ENV.fetch("SANDBOX_REGION", nil)
      ENV["SANDBOX_REGION"] = "eu-west (Frankfurt)"
      assert_equal "eu-west (Frankfurt)", Sandboxes.region(SandboxProviders::DOCKER)

      ENV.delete("SANDBOX_REGION")
      assert_nil Sandboxes.region(SandboxProviders::DOCKER)
      assert_nil Sandboxes.region(nil)
    ensure
      ENV["SANDBOX_REGION"] = given
    end

    private

    def terminal = @terminal ||= Terminal.new(key: "conversation-9", workspace: @workspace)
  end
end
