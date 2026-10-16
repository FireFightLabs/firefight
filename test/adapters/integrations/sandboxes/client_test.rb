require "test_helper"

module Integrations
  module Sandboxes
    # The client against the sandbox's own command service, served here over a real socket. Only who a command runs
    # as is left out, since that needs the box's users.
    class ClientTest < ActiveSupport::TestCase
      KEY = "test-box-key".freeze

      setup do
        load_server
        FileUtils.mkdir_p(::Sandbox::PROGRESS)
        FileUtils.stubs(:chown)
        @replaced = {}
        @server = TCPServer.new("127.0.0.1", 0)
        @accepting = Thread.new { loop { Thread.new(@server.accept) { |socket| ::Sandbox::Http.handle(socket) } } }
        @client = Client.new(Box.new(ref: "box", address: "http://127.0.0.1:#{@server.addr[1]}", key: ::Sandbox::KEY))
        @client.stubs(:pause)
      end

      teardown do
        @accepting.kill
        @server.close
        @replaced.each { |(owner, name), original| owner.define_singleton_method(name, original) }
        FileUtils.rm_rf(Dir.glob(File.join(::Sandbox::PROGRESS, "*")))
      end

      test "a command's progress is heard in whole lines while it runs, and its answer is the same as a plain command's" do
        script = <<~SH
          echo '{"n":1}' >> "$SANDBOX_PROGRESS"
          sleep 0.2
          printf '{"n":2}\\n{"n":' >> "$SANDBOX_PROGRESS"
          sleep 0.2
          printf '3}\\n' >> "$SANDBOX_PROGRESS"
          { head -c #{::Sandbox::Runs::CHUNK + 10} /dev/zero | tr '\\0' x; printf '\\n{"n":4}\\n'; } >> "$SANDBOX_PROGRESS"
          echo done
        SH
        run_as_caller(script)
        heard = []

        result = @client.exec(repository: "acme__api", argv: [ "ignored" ], where: Client::IN_COPY, timeout: 30, on_output: ->(text) { heard << text })

        assert_equal "done\n", result["stdout"]
        assert_equal 0, result["exit_code"]
        lines = heard.join.lines
        assert lines.all? { |line| line.end_with?("\n") }, "only whole lines"
        assert_equal [ 1, 2, 3, 4 ], lines.filter_map { |line| JSON.parse(line)["n"] rescue nil }
        assert heard.size > 2, "heard while it ran, not only at the end"
        assert heard.all? { |text| text.bytesize <= ::Sandbox::Runs::CHUNK }, "no read hands back more than a chunk"
      end

      test "a box is waited for as long as its provider says, and one that never answers says why its last check failed" do
        slow = Client.new(Box.new(ref: "box", address: "http://127.0.0.1:9", key: "k"))
        slow.stubs(:pause).with { travel(40.seconds) || true }
        not_yet = Error.new("could not reach 127.0.0.1 (Errno::ECONNREFUSED)")
        slow.stubs(:send_json).raises(not_yet).then.raises(not_yet).then.raises(not_yet).then.raises(not_yet).then.raises(not_yet)
            .then.raises(not_yet).then.raises(not_yet).then.returns({ "ok" => true })

        error = assert_raises(Error) { slow.wait_until_ready!(within: Client::READY_TIMEOUT) }
        assert_equal "The code sandbox did not come up within 180 seconds: could not reach 127.0.0.1 (Errno::ECONNREFUSED).", error.message

        slow.stubs(:send_json).raises(not_yet).then.raises(not_yet).then.raises(not_yet).then.raises(not_yet).then.raises(not_yet)
            .then.raises(not_yet).then.raises(not_yet).then.returns({ "ok" => true })
        assert_nothing_raised { slow.wait_until_ready!(within: 15.minutes.to_i) }
      end

      test "a command that fails to start answers its refusal" do
        replace(::Sandbox::Handler, :exec) { |_request, **| raise ::Sandbox::Refused, "acme__api has no commit nope" }

        error = assert_raises(Error) { @client.exec(repository: "acme__api", argv: [ "x" ], ref: "nope", on_output: ->(_text) { }) }

        assert_equal "acme__api has no commit nope", error.message
      end

      test "a box from an older image, which cannot run commands in the background, runs it in one request as before" do
        replace(::Sandbox::Handler, :call) do |method, path, body, _query = {}|
          case [ method, path ]
          in [ "GET", "/health" ] then { "ok" => true }
          in [ "POST", "/exec" ] then { "stdout" => "old #{JSON.parse(body)['argv'].join}", "exit_code" => 0 }
          else raise ::Sandbox::Refused, "No route #{method} #{path}"
          end
        end
        heard = []

        result = @client.exec(repository: "acme__api", argv: [ "x" ], on_output: ->(text) { heard << text })

        assert_equal "old x", result["stdout"]
        assert_empty heard
      end

      # Seen live: a check from outside held a chat's turn for minutes after the person pressed Stop.
      test "a stop while a command runs ends the command in the box and the wait at once" do
        run_as_caller("echo started >> \"$SANDBOX_PROGRESS\"; sleep 30; echo never")
        signal = Concurrent::Event.new
        before = ::Sandbox::Runs::STORE.keys
        started = clock

        assert_raises(StopSignal::Stopped) do
          StopSignal.watching(signal) do
            @client.exec(repository: "acme__api", argv: [ "x" ], where: Client::IN_COPY, timeout: 60, on_output: ->(text) { signal.set if text.include?("started") })
          end
        end

        assert_operator clock - started, :<, 10
        run = ::Sandbox::Runs::STORE.except(*before).values.find { |entry| entry["stopped"] }
        assert run, "the box was told to stop the command"
        Timeout.timeout(10) { Thread.pass until run["finished_at"] }
        assert_equal ::Sandbox::Runs::STOPPED, run["result"]["error"]
        assert_operator clock - started, :<, 10, "the command was ended, not left to sleep out its 30 seconds"
      end

      test "a stop that reaches a run after its commands ended signals no process, since their ids may belong to others by then" do
        run_as_caller("true; echo done")
        started = ::Sandbox::Runs.start({ "repo" => "acme__api", "argv" => [ "x" ] })
        entry = ::Sandbox::Runs::STORE.fetch(started["id"])
        Timeout.timeout(10) { Thread.pass until entry["finished_at"] }
        assert_empty entry["pids"], "a command's id is let go once it is reaped"

        Process.expects(:kill).never
        assert_equal({ "stopped" => false }, ::Sandbox::Runs.stop(started["id"]))
        assert_equal "done\n", entry["result"]["stdout"]
      end

      test "a command in the terminal is followed in the background on a box that can, so a stop reaches it" do
        run_as_caller("sleep 30")
        signal = Concurrent::Event.new
        Concurrent::ScheduledTask.execute(0.5) { signal.set }
        started = clock

        assert_raises(StopSignal::Stopped) { StopSignal.watching(signal) { @client.terminal(argv: [ "x" ], timeout: 60) } }

        assert_operator clock - started, :<, 10
      end

      test "a box from an image that cannot stop a command is no longer waited for" do
        run_as_caller("sleep 2")
        served = ::Sandbox::Handler.method(:call)
        replace(::Sandbox::Handler, :call) do |method, path, body, query = {}|
          raise ::Sandbox::Refused, "No route #{method} #{path}" if method == "DELETE"

          answer = served.call(method, path, body, query)
          path == "/health" ? answer.except("stops") : answer
        end
        signal = Concurrent::Event.new
        signal.set
        before = ::Sandbox::Runs::STORE.keys

        assert_raises(StopSignal::Stopped) { StopSignal.watching(signal) { @client.terminal(argv: [ "x" ], timeout: 60) } }
        assert_not(::Sandbox::Runs::STORE.except(*before).values.any? { |entry| entry["stopped"] })
      end

      test "an answer is kept for a reader that asks again, and a finished one is swept after a while" do
        run_as_caller("echo '{}' >> \"$SANDBOX_PROGRESS\"; echo hi")
        started = ::Sandbox::Runs.start({ "repo" => "acme__api", "argv" => [ "x" ] })
        Timeout.timeout(10) { Thread.pass until ::Sandbox::Runs.read(started["id"], 0)["done"] }
        path = ::Sandbox::Runs::STORE.fetch(started["id"])["path"]

        assert_equal "hi\n", ::Sandbox::Runs.read(started["id"], 0)["result"]["stdout"]
        assert_equal "hi\n", ::Sandbox::Runs.read(started["id"], 0)["result"]["stdout"]

        travel ::Sandbox::Runs::KEPT_FOR + 1.minute do
          ::Sandbox::Runs.sweep
        end
        assert_raises(::Sandbox::Refused) { ::Sandbox::Runs.read(started["id"], 0) }
        refute File.exist?(path)
      end

      private

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # The service reads its key and where it keeps progress when it loads, once per test process.
      def load_server
        return if defined?(::Sandbox::Runs)

        given = ENV.to_h.slice("SANDBOX_KEY", "SANDBOX_PROGRESS_DIR")
        ENV["SANDBOX_KEY"] = KEY
        ENV["SANDBOX_PROGRESS_DIR"] = Dir.mktmpdir("sandbox-progress")
        load Rails.root.join("sandbox/server.rb").to_s
      ensure
        %w[SANDBOX_KEY SANDBOX_PROGRESS_DIR].each { |name| ENV[name] = given[name] } if given
      end

      # Runs the script as whoever runs the test, which the box would run as runner.
      def run_as_caller(script)
        replace(::Sandbox::Handler, :exec) do |_request, progress: nil|
          ::Sandbox.run([ "bash", "-c", script ], timeout: 20, env: { "SANDBOX_PROGRESS" => progress })
        end
      end

      def replace(owner, name, &block)
        @replaced[[ owner, name ]] ||= owner.method(name)
        owner.define_singleton_method(name, &block)
      end
    end
  end
end
