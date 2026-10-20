require "socket"
require "websocket/driver"

module Integrations
  module Http
    # What a provider's live address sends over a WebSocket until it closes, for a provider that hands out a short-lived
    # signed address to read a running thing's output, such as a deployment's log while it builds. Like a signed file
    # (Http.download), it is reached without the provider's credentials, only encrypted (wss, or https taken as wss as the
    # provider's own clients do) and on a public address, and read for at most seconds or limit bytes, whichever comes first.
    module LiveSocket
      CHUNK = 16_384
      SECURE = %w[wss https].freeze

      # The socket websocket-driver writes its frames to.
      Wire = Data.define(:url, :io) do
        def write(data) = io.write(data)
      end

      # Every message the address sent before it closed or the read stopped, in order.
      def self.messages(url, provider_key:, error_class:, limit:, seconds:)
        uri = URI.parse(url.to_s)
        raise error_class, "The live address is not encrypted." unless SECURE.include?(uri.scheme) && uri.host.present?

        uri.scheme = "wss"
        address = PublicAddress.check!(uri.host, provider_key: provider_key).ip.to_s
        io = connect(uri, address, seconds)
        read(io, uri, limit, Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds, error_class)
      rescue PublicAddress::Refused => error
        raise error_class, error.message
      rescue URI::InvalidURIError
        raise error_class, "The live address could not be read."
      rescue SystemCallError, SocketError, OpenSSL::SSL::SSLError, IOError, Timeout::Error => error
        raise error_class, "could not reach #{uri&.host} (#{error.class.name})"
      ensure
        io&.close
      end

      def self.connect(uri, address, seconds)
        tcp = Socket.tcp(address, uri.port || 443, connect_timeout: [ OPEN_TIMEOUT, seconds ].min)
        context = OpenSSL::SSL::SSLContext.new
        context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
        ssl = OpenSSL::SSL::SSLSocket.new(tcp, context)
        ssl.hostname = uri.host
        ssl.sync_close = true
        Timeout.timeout(seconds) { ssl.connect }
        ssl.post_connection_check(uri.host)
        ssl
      end

      # Frames are parsed as they arrive, and the read stops at the close frame, the end of the stream, the deadline or
      # once limit bytes of messages are kept.
      def self.read(io, uri, limit, deadline, error_class)
        driver = WebSocket::Driver.client(Wire.new(url: uri.to_s, io: io))
        kept = []
        bytes = 0
        closed = false
        failed = nil
        driver.on(:message) do |event|
          kept << event.data.to_s
          bytes += event.data.to_s.bytesize
        end
        driver.on(:close) { closed = true }
        driver.on(:error) { |event| failed = event.message }
        driver.start
        until closed || bytes >= limit
          left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if left <= 0
          break unless io.pending.positive? || IO.select([ io ], nil, nil, left)

          data = io.read_nonblock(CHUNK, exception: false)
          next if data == :wait_readable
          break if data.nil?

          driver.parse(data)
          raise error_class, "The live address answered with something that is not a WebSocket: #{failed}" if failed && kept.empty?
        end
        kept
      end
      private_class_method :connect, :read
    end
  end
end
