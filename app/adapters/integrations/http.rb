module Integrations
  # The one Net::HTTP transport for integration adapters: TLS, timeouts, and
  # network failures mapped onto the caller's own error class. Response
  # handling stays with the caller; only reaching the host is shared.
  module Http
    OPEN_TIMEOUT = 5

    def self.request(uri, request, error_class:, read_timeout: 15)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: OPEN_TIMEOUT, read_timeout: read_timeout) do |connection|
        connection.request(request)
      end
    rescue Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError => e
      raise error_class, "could not reach #{uri.host} (#{e.class.name})"
    end
  end
end
