module Integrations
  # Only reaching the host is shared. Response handling stays with the caller.
  module Http
    OPEN_TIMEOUT = 5

    # ipaddr connects to an address checked beforehand (PublicAddress.check!), keeping the host name for the certificate.
    # cert_store holds the certificates to trust, for a server whose certificate a workspace pasted.
    def self.request(uri, request, error_class:, read_timeout: 15, ipaddr: nil, cert_store: nil)
      options = { use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: read_timeout, ipaddr: ipaddr, cert_store: cert_store }.compact
      Net::HTTP.start(uri.hostname, uri.port, **options) do |connection|
        connection.request(request)
      end
    rescue Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError => e
      raise error_class, "could not reach #{uri.host} (#{e.class.name})"
    end
  end
end
