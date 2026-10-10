require "test_helper"

module Integrations
  module Sandboxes
    # Firefight's own command line in the sandbox image (sandbox/bin/ff), against a stand-in for the relay over a real
    # socket, so what it sends and how it exits are what a script in Halon's terminal sees.
    class FfTest < ActiveSupport::TestCase
      FF = Rails.root.join("sandbox/bin/ff").to_s

      setup do
        @requests = []
        @answers = {}
        @server = TCPServer.new("127.0.0.1", 0)
        requests = @requests
        answers = @answers
        @accepting = Thread.new do
          loop do
            socket = @server.accept
            line = socket.gets("\r\n").to_s
            headers = {}
            while (header = socket.gets("\r\n")) && header != "\r\n"
              key, value = header.split(":", 2)
              headers[key.strip.downcase] = value.to_s.strip
            end
            body = headers["content-length"].to_i.positive? ? socket.read(headers["content-length"].to_i) : ""
            method, target = line.split(" ", 3)
            requests << { method: method, target: target, authorization: headers["authorization"], body: body }
            status, payload = answers.fetch(target.split("?").first, [ 404, { "error" => "No tool called that." } ])
            json = JSON.generate(payload)
            socket.write("HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nContent-Length: #{json.bytesize}\r\nConnection: close\r\n\r\n#{json}")
            socket.close
          end
        end
      end

      teardown do
        @accepting.kill
        @server.close
      end

      test "a tool is called with its arguments on the command's token, and the answer is printed as given" do
        @answers["/relay/tools/fake_echo_text"] = [ 200, { "outcome" => "ok", "text" => "echo: hi" } ]

        output, status = ff("fake_echo_text", "text=hi", "limit=5", "names=[\"a\"]")

        assert_equal [ "echo: hi\n", 0 ], [ output, status.exitstatus ]
        sent = @requests.sole
        assert_equal [ "POST", "Bearer tok" ], [ sent[:method], sent[:authorization] ]
        assert_equal({ "arguments" => { "text" => "hi", "limit" => 5, "names" => [ "a" ] } }, JSON.parse(sent[:body]))
      end

      test "a refusal exits 1 and a call held for an approval exits 3, so a script can tell" do
        @answers["/relay/tools/change"] = [ 200, { "outcome" => "refused", "text" => "change changes something, so it was not run." } ]
        @answers["/relay/tools/held"] = [ 200, { "outcome" => "waiting", "text" => "Needs an approval and was not run: x." } ]

        assert_equal 1, ff("change").last.exitstatus
        assert_equal 3, ff("held").last.exitstatus
      end

      test "the tools are listed a line each, and a relay that refuses the token is said" do
        @answers["/relay/tools"] = [ 200, { "tools" => [ { "name" => "fake_echo_text", "reads" => true, "description" => "Echoes" } ] } ]
        assert_equal "fake_echo_text  (reads)  Echoes\n", ff("tools").first

        @answers["/relay/clis"] = [ 401, { "error" => "This command has ended." } ]
        output, status = ff("with", "northflank", "--", "true")
        assert_equal 1, status.exitstatus
        assert_includes output, "This command has ended."
      end

      private

      def ff(*args)
        env = { "FIREFIGHT_RELAY_URL" => "http://127.0.0.1:#{@server.addr[1]}/relay", "FIREFIGHT_RELAY_TOKEN" => "tok" }
        Open3.capture2e(env, RbConfig.ruby, FF, *args)
      end
    end
  end
end
