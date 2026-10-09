module Integrations
  # Reaching a provider's host, and the parts of reading its answer every client shares: JSON with its errors mapped,
  # a 429 as RateLimited, and a file at a signed address. How a provider words its reason stays with its own client.
  module Http
    OPEN_TIMEOUT = 5
    TOO_MANY_REQUESTS = 429
    NOT_FOUND = 404
    # What a redirect to stored content keeps by default, the tail of a log where it says why something failed.
    DOWNLOAD_LIMIT = 2_000_000
    REDIRECTS = [ 301, 302, 303, 307, 308 ].freeze
    # The fields providers most often put their reason in, tried in order when a client says nothing of its own. Each may
    # hold the words, an object with a message or detail, or a list of either. OAuth's error_description is the readable
    # one (RFC 6749, section 5.2), and its error only a code, so the description comes first.
    REASON_FIELDS = %w[error_description error message detail errors].freeze
    # An answer with its status and headers, for a caller that tells answers apart by status (202 queued from 201 done)
    # or reads a header, such as the next page's number. Header names are lower case.
    Answer = Data.define(:status, :body, :headers) do
      def initialize(headers: {}, **) = super

      def header(name) = headers[name.to_s.downcase]
    end
    REASON = ->(body) { REASON_FIELDS.lazy.filter_map { |field| Http.words(body[field]) }.first }

    # A reason as words, from a string, an object with a message, detail, title or description, or a list of them, each
    # without its closing period and joined with commas.
    def self.words(value)
      case value
      when String then value.strip.presence
      when Hash then %w[message detail title description error].lazy.filter_map { |key| words(value[key]) }.first
      when Array then value.filter_map { |each| Sentence.clean(words(each)) }.uniq.join(", ").presence
      end
    end

    # ipaddr connects to an address checked beforehand (PublicAddress.check!), keeping the host name for the certificate.
    # cert_store holds the certificates to trust, for a server whose certificate a workspace pasted. A block is handed
    # the response as it arrives, for an answer read as a stream.
    def self.request(uri, request, error_class:, read_timeout: 15, ipaddr: nil, cert_store: nil, &)
      options = { use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: read_timeout, ipaddr: ipaddr, cert_store: cert_store }.compact
      Net::HTTP.start(uri.hostname, uri.port, **options) do |connection|
        connection.request(request, &)
      end
    rescue Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError, IOError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Zlib::Error => error
      raise error_class, "could not reach #{uri.host} (#{error.class.name})"
    end

    # The answer read as JSON. A 2xx answer that is not JSON still counts as done and reads as {}, so a change that went
    # through is never reported as failed. Anything else raises "<provider> answered <code>: <reason>", RateLimited for a
    # 429, the class refine names for the code and reason, or error_class. reason reads the provider's own words from
    # the parsed body. A 429 is rate_limited (error_class unless given), marked RateLimited, and a 404 is marked NotFound.
    # with_status answers an Answer holding the status, the body and the headers. as: :text answers a 2xx body as the text it is, for an endpoint that
    # answers text such as a log, with errors read the same way. redirect: :download follows a redirect the provider
    # documents to stored content through download (https only, a public address, no credentials), for provider_key,
    # keeping its last download_limit bytes as text.
    def self.json(uri, request, error_class:, provider_name:, reason: REASON, refine: nil, rate_limited: nil, read_timeout: 30, with_status: false,
                  as: :json, redirect: nil, provider_key: nil, download_limit: DOWNLOAD_LIMIT, **)
      raise ArgumentError, "following a redirect to download needs the provider_key its address is checked for" if redirect == :download && provider_key.blank?

      response = self.request(uri, request, error_class: error_class, read_timeout: read_timeout, **)
      code = response.code.to_i
      if redirect == :download && REDIRECTS.include?(code)
        stored = download(URI.join(uri.to_s, response["location"].to_s).to_s, provider_key: provider_key, error_class: error_class, limit: download_limit)
        return with_status ? Answer.new(status: code, body: stored, headers: headers_of(response)) : stored
      end

      body = parsed(response.body)
      if code.between?(200, 299)
        kept = as == :text ? String.new(response.body.to_s, encoding: Encoding::UTF_8).scrub : body || {}
        return with_status ? Answer.new(status: code, body: kept, headers: headers_of(response)) : kept
      end

      said = (body.is_a?(Hash) && reason.call(body)).presence || "no reason given"
      raise (rate_limited || error_class).new("#{provider_name} answered #{code}: #{said}").extend(RateLimited) if code == TOO_MANY_REQUESTS
      raise error_class, "#{provider_name} answered #{code} with something that is not JSON" unless body

      error = (refine&.call(code, said) || error_class).new("#{provider_name} answered #{code}: #{said}")
      raise code == NOT_FOUND ? error.extend(NotFound) : error
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

    def self.headers_of(response)
      return {} unless response.respond_to?(:to_hash)

      response.to_hash.to_h { |name, values| [ name.to_s.downcase, Array(values).join(", ") ] }
    end

    def self.parsed(text)
      text.to_s.strip.empty? ? nil : JSON.parse(text)
    rescue JSON::ParserError
      nil
    end
    private_class_method :parsed, :headers_of
  end
end
