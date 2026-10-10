require "test_helper"

module Integrations
  module Sandboxes
    # Halon's terminal in the sandbox's command service, against the service itself over a real socket. Who a command
    # runs as is left out, since that needs the box's users, and the terminal's folder is a temporary one here.
    class TerminalTest < ActiveSupport::TestCase
      setup do
        load_server
        FileUtils.stubs(:chown)
        @replaced = {}
        @constants = {}
        @root = Dir.mktmpdir("sandbox-terminal")
        set_constant(::Sandbox, :TERMINAL, File.join(@root, "terminal"))
        set_constant(::Sandbox, :TERMINAL_FILES, File.join(@root, "terminal", "results"))
        ran = @ran = []
        original = ::Sandbox.method(:run)
        replace(::Sandbox, :run) do |argv, **options|
          ran << options.merge(argv: argv)
          original.call(argv, **options, user: nil)
        end
        @server = TCPServer.new("127.0.0.1", 0)
        @accepting = Thread.new { loop { Thread.new(@server.accept) { |socket| ::Sandbox::Http.handle(socket) } } }
        @client = Client.new(Box.new(ref: "box", address: "http://127.0.0.1:#{@server.addr[1]}", key: ::Sandbox::KEY))
      end

      teardown do
        @accepting.kill
        @server.close
        @replaced.each { |(owner, name), original| owner.define_singleton_method(name, original) }
        @constants.each { |(owner, name), value| set_constant(owner, name, value, keep: false) }
        FileUtils.rm_rf(@root)
      end

      test "the box says it has the terminal, and a placed file is read by a command in the terminal's folder with what it was handed" do
        assert @client.terminal?

        placed = @client.place_file("result_2.txt", "a 500\nb 200\nc 500\n")
        said = @client.terminal(argv: [ "bash", "-c", "grep -c 500 results/result_2.txt && echo \"$FIREFIGHT_RELAY_URL\"" ],
                                env: { "FIREFIGHT_RELAY_URL" => "https://ff.example/sandbox_relay" })

        assert_equal File.join(@root, "terminal", "results", "result_2.txt"), placed["path"]
        assert_equal [ 0, "2\nhttps://ff.example/sandbox_relay\n" ], [ said["exit_code"], said["stdout"] ]
        assert_equal [ File.join(@root, "terminal"), ::Sandbox::TERMINAL_USER ], [ @ran.last[:dir], @ran.last[:user] ]
      end

      test "a command in the background is followed to its answer" do
        heard = []
        said = @client.terminal(argv: [ "bash", "-c", "echo done" ], on_output: ->(line) { heard << line })

        assert_equal "done\n", said["stdout"]
        assert heard.any?, "the background run was read at least once"
      end

      test "a variable the image sets, a name that is not a variable's and a file name with a path are refused" do
        assert_match "PATH", assert_raises(Error) { @client.terminal(argv: [ "env" ], env: { "PATH" => "/tmp" }) }.message
        assert_match "lower", assert_raises(Error) { @client.terminal(argv: [ "env" ], env: { "lower" => "x" }) }.message
        assert_match "Not a file name", assert_raises(Error) { @client.place_file("..%2Fescape", "x") }.message
      end

      private

      def load_server
        return if defined?(::Sandbox::Runs)

        given = ENV.to_h.slice("SANDBOX_KEY", "SANDBOX_PROGRESS_DIR")
        ENV["SANDBOX_KEY"] = "test-box-key"
        ENV["SANDBOX_PROGRESS_DIR"] = Dir.mktmpdir("sandbox-progress")
        load Rails.root.join("sandbox/server.rb").to_s
      ensure
        %w[SANDBOX_KEY SANDBOX_PROGRESS_DIR].each { |name| ENV[name] = given[name] } if given
      end

      def replace(owner, name, &block)
        @replaced[[ owner, name ]] ||= owner.method(name)
        owner.define_singleton_method(name, &block)
      end

      def set_constant(owner, name, value, keep: true)
        @constants[[ owner, name ]] ||= owner.const_get(name) if keep
        owner.send(:remove_const, name)
        owner.const_set(name, value)
      end
    end
  end
end
