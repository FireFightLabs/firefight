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

      test "every labelled container is held, stopped ones too, with its state in one vocabulary" do
        asked = nil
        Docker.any_instance.stubs(:request).with { |_verb, path| asked = path }.returns([
          { "Id" => "abc123", "Names" => [ "/halon-box-1" ], "State" => "exited", "Created" => 1_790_000_000 }
        ])

        held = Docker.new.inventory.sole

        assert_includes asked, "all=true"
        assert_equal [ "abc123", "halon-box-1", "exited", ProviderSandbox::PHASE_STOPPED ], [ held.ref, held.name, held.state, held.phase ]
      end

      test "a box is labelled with the workspace and run it was started for, and the labels are read back" do
        owner = Owner.new(workspace_id: "0b6f6c1e-58d4-4a8e-9a43-1f1f2b0c9d11", key: "investigation-5d1e2f30-9c4b-4d0e-8f7a-2b3c4d5e6f70")
        sent = []
        Docker.any_instance.stubs(:request).with { |_verb, _path, payload = nil| sent << payload }
              .returns({ "Id" => "abc123" }, {}, { "NetworkSettings" => { "Ports" => { "8080/tcp" => [ { "HostIp" => "127.0.0.1", "HostPort" => "49153" } ] } } })

        Docker.new.start(name: "halon-box-1", owner: owner)

        labels = sent.first[:Labels]
        assert_equal({ "firefight.sandbox" => "1", "firefight.workspace" => owner.workspace_id, "firefight.box-key" => owner.key }, labels)
        Docker.any_instance.stubs(:request).returns([
          { "Id" => "abc123", "Names" => [ "/halon-box-1" ], "State" => "running", "Created" => 1_790_000_000, "Labels" => labels },
          { "Id" => "def456", "Names" => [ "/halon-box-2" ], "State" => "running", "Created" => 1_790_000_000, "Labels" => { "firefight.sandbox" => "1" } }
        ])
        assert_equal [ owner, nil ], Docker.new.inventory.map(&:owner)
      end

      test "a box is handed back with the key in its own configuration" do
        Docker.any_instance.stubs(:request).with(Net::HTTP::Get, "/containers/abc123/json").returns(
          { "Name" => "/halon-box-1", "Config" => { "Env" => [ "PATH=/usr/bin", "SANDBOX_KEY=k-lost" ] },
            "NetworkSettings" => { "Ports" => { "8080/tcp" => [ { "HostIp" => "127.0.0.1", "HostPort" => "49153" } ] } } }
        )

        box = Docker.new.reclaim("abc123")

        assert_equal [ "k-lost", "http://127.0.0.1:49153" ], [ box.key, box.address ]
      end

      test "a daemon that cannot be reached says where it looked" do
        ENV.stubs(:[]).with("DOCKER_HOST").returns("unix:///nowhere/docker.sock")

        error = assert_raises(Error) { Docker.new.running }
        assert_match "/nowhere/docker.sock", error.message
      end
    end
  end
end
