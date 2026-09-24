require "test_helper"

module Integrations
  module Sandboxes
    class DockerTest < ActiveSupport::TestCase
      setup do
        ENV.stubs(:[]).with(anything).returns(nil)
      end

      test "a box starts from the sandbox image, labelled, with its key only in its environment, published on loopback" do
        sent = []
        Docker.any_instance.stubs(:request).with { |verb, path, payload = nil| sent << [ verb, path, payload ] }
              .returns({ "Id" => "abc123" }, {}, { "NetworkSettings" => { "Ports" => { "8080/tcp" => [ { "HostIp" => "127.0.0.1", "HostPort" => "49153" } ] } } })

        box = Docker.new.start(name: "halon-box-1")

        _verb, path, payload = sent.first
        assert_equal "/containers/create?name=halon-box-1", path
        assert_equal Sandboxes.image, payload[:Image]
        assert_equal [ "SANDBOX_KEY=#{box.key}" ], payload[:Env]
        assert_equal({ "firefight.sandbox" => "1" }, payload[:Labels])
        assert_equal [ { HostIp: "127.0.0.1", HostPort: "" } ], payload.dig(:HostConfig, :PortBindings, "8080/tcp")
        assert_equal "/containers/abc123/start", sent.second[1]
        assert_equal "http://127.0.0.1:49153", box.address
      end

      test "on the app's own network a box is reached by its name" do
        ENV.stubs(:[]).with("SANDBOX_DOCKER_NETWORK").returns("firefight")
        sent = []
        Docker.any_instance.stubs(:request).with { |verb, path, payload = nil| sent << payload }.returns({ "Id" => "abc123" }, {})

        box = Docker.new.start(name: "halon-box-1")

        assert_equal "firefight", sent.first.dig(:HostConfig, :NetworkMode)
        assert_equal "http://halon-box-1:8080", box.address
      end

      test "stopping a box that is already gone is not an error" do
        Docker.any_instance.stubs(:request).raises(Error, "Docker 404: No such container: abc123")

        assert_nothing_raised { Docker.new.stop("abc123") }
      end

      test "only labelled boxes are listed, with when each started" do
        Docker.any_instance.expects(:request).with(Net::HTTP::Get, "/containers/json?filters=%7B%22label%22%3A%5B%22firefight.sandbox%3D1%22%5D%7D")
              .returns([ { "Id" => "abc123", "Created" => 1_790_000_000 } ])

        running = Docker.new.running.sole
        assert_equal "abc123", running.ref
        assert_equal Time.zone.at(1_790_000_000), running.started_at
      end

      test "a daemon that cannot be reached says where it looked" do
        ENV.stubs(:[]).with("DOCKER_HOST").returns("unix:///nowhere/docker.sock")

        error = assert_raises(Error) { Docker.new.running }
        assert_match "/nowhere/docker.sock", error.message
      end
    end
  end
end
