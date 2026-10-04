module Integrations
  # Reaching a provider's host, and the parts of reading its answer every client shares: JSON with its errors mapped,
  # a 429 as RateLimited, and a file at a signed address. How a provider words its reason stays with its own client.
  module Http
    OPEN_TIMEOUT = 5
    TOO_MANY_REQUESTS = 429
    # The fields providers most often put their reason in, tried in order when a client says nothing of its own.
    REASON = ->(body) { body.dig("error", "message") || body["message"] || body["error_description"] || body["detail"] || body["error"].presence }

    # ipaddr connects to an address checked beforehand (PublicAddress.check!), keeping the host name for the certificate.
    # cert_store holds the certificates to trust, for a server whose certificate a workspace pasted. A block is handed
    # the response as it arrives, for an answer read as a stream.
    def self.request(uri, request, error_class:, read_timeout: 15, ipaddr: nil, cert_store: nil, &)
      options = { use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: read_timeout, ipaddr: ipaddr, cert_store: cert_store }.compact
      Net::HTTP.start(uri.hostname, uri.port, **options) do |connection|
        connection.request(request, &)
      end
    rescue Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError => e
      raise error_class, "could not reach #{uri.host} (#{e.class.name})"
    end

    # The answer read as JSON. A 2xx answer that is not JSON still counts as done and reads as {}, so a change that went
    # through is never reported as failed. Anything else raises "<provider> answered <code>: <reason>", RateLimited for a
    # 429, the class refine names for the code and reason, or error_class. reason reads the provider's own words from
    # the parsed body. A 429 is rate_limited (error_class unless given), marked RateLimited.
    def self.json(uri, request, error_class:, provider_name:, reason: REASON, refine: nil, rate_limited: nil, read_timeout: 30, **)
      response = self.request(uri, request, error_class: error_class, read_timeout: read_timeout, **)
      code = response.code.to_i
      body = parsed(response.body)
      return body || {} if code.between?(200, 299)

      said = (body.is_a?(Hash) && reason.call(body)).presence || "no reason given"
      raise (rate_limited || error_class).new("#{provider_name} answered #{code}: #{said}").extend(RateLimited) if code == TOO_MANY_REQUESTS
      raise error_class, "#{provider_name} answered #{code} with something that is not JSON" unless body

      raise refine&.call(code, said) || error_class, "#{provider_name} answered #{code}: #{said}"
    end

    # A file at a short-lived signed address a provider handed over, such as a job's log. It is fetched without the
    # provider's credentials, only over https and on a public address (PublicAddress), and cut to its last limit bytes,
    # where a log says why something failed.
    def self.download(url, provider_key:, error_class:, limit:, read_timeout: 30)
      uri = URI.parse(url.to_s)
      raise error_class, "The file is at an address that is not https." unless uri.is_a?(URI::HTTPS) && uri.host.present?

      address = PublicAddress.check!(uri.host, provider_key: provider_key).ip.to_s
      file = self.request(uri, Net::HTTP::Get.new(uri), error_class: error_class, read_timeout: read_timeout, ipaddr: address)
      raise error_class, "The file's address answered #{file.code}." unless file.code.to_i.between?(200, 299)

      body = String.new(file.body.to_s, encoding: Encoding::UTF_8).scrub
      body.bytesize > limit ? body.byteslice(-limit, limit).scrub : body
    rescue PublicAddress::Refused => error
      raise error_class, error.message
    rescue URI::InvalidURIError
      raise error_class, "The file's address could not be read."
    end

    # One segment of a path, escaped, so a name with a slash or a space stays one segment.
    def self.segment(value) = ERB::Util.url_encode(value.to_s)

    def self.parsed(text)
      text.to_s.strip.empty? ? nil : JSON.parse(text)
    rescue JSON::ParserError
      nil
    end
    private_class_method :parsed
  end
end
