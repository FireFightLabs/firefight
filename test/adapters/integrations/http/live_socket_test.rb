require "test_helper"
require "socket"

module Integrations
  module Http
    class LiveSocketTest < ActiveSupport::TestCase
      class Error < Integrations::Error; end

      ServerWire = Data.define(:io) do
        def write(data) = io.write(data)
      end

      test "every message the address sends before it closes is read, through the checked address" do
        client, server = UNIXSocket.pair
        client.define_singleton_method(:pending) { 0 }
        PublicAddress.expects(:check!).with("logs.example", provider_key: "digitalocean").returns(PublicAddress::Checked.new(ip: IPAddr.new("203.0.113.5"), private: false))
        LiveSocket.expects(:connect).with { |uri, address, _seconds| uri.to_s == "wss://logs.example/live?token=t" && address == "203.0.113.5" }.returns(client)
        serving = Thread.new { serve(server, [ { data: "one\n" }.to_json, { data: "two\n" }.to_json ]) }

        messages = LiveSocket.messages("https://logs.example/live?token=t", provider_key: "digitalocean", error_class: Error, limit: 1_000, seconds: 5)

        assert_equal [ { data: "one\n" }.to_json, { data: "two\n" }.to_json ], messages
      ensure
        serving&.join(5)
        server&.close
      end

      test "an address that is not encrypted or is private is refused before anything connects" do
        LiveSocket.expects(:connect).never
        assert_match "not encrypted", assert_raises(Error) { LiveSocket.messages("ws://logs.example/live", provider_key: "digitalocean", error_class: Error, limit: 10, seconds: 1) }.message

        PublicAddress.stubs(:check!).raises(PublicAddress::Refused, "logs.example is on a private network, which Firefight does not connect to.")
        assert_match "private network", assert_raises(Error) { LiveSocket.messages("wss://logs.example/live", provider_key: "digitalocean", error_class: Error, limit: 10, seconds: 1) }.message
      end

      test "a handshake that fails closes the socket it opened" do
        Socket.stubs(:tcp).returns(mock("tcp"))
        ssl = mock("ssl")
        OpenSSL::SSL::SSLSocket.stubs(:new).returns(ssl)
        ssl.stubs(:hostname=)
        ssl.stubs(:sync_close=)
        ssl.stubs(:connect).raises(OpenSSL::SSL::SSLError, "handshake failed")
        # sync_close is set, so closing the TLS socket closes the TCP one beneath it.
        ssl.expects(:close).once
        PublicAddress.stubs(:check!).returns(PublicAddress::Checked.new(ip: IPAddr.new("203.0.113.5"), private: false))

        assert_raises(Error) { LiveSocket.messages("wss://logs.example/live", provider_key: "digitalocean", error_class: Error, limit: 10, seconds: 1) }
      end

      private

      # A WebSocket server on the other end that sends each message, then closes.
      def serve(io, messages)
        driver = WebSocket::Driver.server(ServerWire.new(io: io))
        closed = false
        driver.on(:connect) { driver.start }
        driver.on(:open) do
          messages.each { |message| driver.text(message) }
          driver.close
        end
        driver.on(:close) { closed = true }
        until closed
          data = io.readpartial(16_384)
          driver.parse(data)
        end
      rescue EOFError, IOError
        nil
      end
    end
  end
end
