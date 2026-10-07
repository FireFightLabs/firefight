require "base64"

module Integrations
  # Calls a cluster's API server with a service account token. It trusts only the cluster's own CA, as kubectl does with
  # certificate-authority-data, and Net::HTTP checks the server's certificate and name against it. A private address
  # needs an operator's allowance. Paths and patch types come from the Kubernetes API reference.
  class KubernetesApi
    class Error < Integrations::Error; end
    class Forbidden < Error; end
    class NotFound < Error
      include Integrations::NotFound
    end
    class Unauthorized < Error; end
    # The version a watch started from is older than the API server keeps, so the list has to be read again in full.
    class Gone < Error; end

    PROVIDER_KEY = "kubernetes".freeze
    PATCH_JSON = "application/json-patch+json".freeze
    PATCH_MERGE = "application/merge-patch+json".freeze
    PATCH_STRATEGIC = "application/strategic-merge-patch+json".freeze
    PATCH_TYPES = [ PATCH_JSON, PATCH_MERGE, PATCH_STRATEGIC ].freeze
    PAGE_SIZE = 500
    MAX_PAGES = 10
    READ_TIMEOUT = 30
    CERTIFICATE = /-----BEGIN CERTIFICATE-----(.+?)-----END CERTIFICATE-----/m
    PROVIDER_NAME = "The API server".freeze
    # The API server answers a failure as a Status object, whose message says what was refused and why.
    REFINED = { 401 => Unauthorized, 403 => Forbidden, 404 => NotFound, 410 => Gone }.freeze
    # A watch the API server ends after this many seconds, with the time a quiet stream may be silent beyond it.
    WATCH_SECONDS = 50
    WATCH_MARGIN = 15
    WATCH_ERROR = "ERROR".freeze

    # Why a server address and CA cannot be used, or nil. Read before anything is saved, so it is said on the form.
    def self.refusal(server, ca)
      new(server: server, token: "", ca: ca)
      nil
    rescue Error => error
      error.message
    end

    # The CA certificates pasted, as a PEM bundle or as the base64 kubeconfig keeps in certificate-authority-data. Each
    # certificate is read from what lies between its markers, so a PEM pasted with its line breaks lost still reads.
    def self.certificates(ca)
      text = ca.to_s.strip
      text = Base64.strict_decode64(text.gsub(/\s+/, "")) unless text.include?("-----BEGIN")
      found = text.scan(CERTIFICATE).map { |(body)| OpenSSL::X509::Certificate.new(Base64.strict_decode64(body.gsub(/\s+/, ""))) }
      raise Error, "The CA certificate holds no certificate. Paste certificate-authority-data from your kubeconfig, or the CA in PEM." if found.empty?

      found
    rescue ArgumentError, OpenSSL::X509::CertificateError
      raise Error, "The CA certificate could not be read. Paste certificate-authority-data from your kubeconfig, or the CA in PEM."
    end

    def initialize(server:, token:, ca:)
      @root = parse(server)
      @token = token
      @store = OpenSSL::X509::Store.new
      self.class.certificates(ca).each { |certificate| @store.add_cert(certificate) }
      @ipaddr = address(@root.host)
    end

    def host = @root.host

    def get(path, query = {}) = json(Net::HTTP::Get, path, query)

    # Every item of a list, a page at a time, as a Pages::Read that says when it stopped at MAX_PAGES.
    def list(path, query = {})
      Pages.read(max_pages: MAX_PAGES) do |token|
        page = get(path, query.merge("limit" => PAGE_SIZE, "continue" => token).compact)
        [ page["items"], page.dig("metadata", "continue") ]
      end
    end

    # What an endpoint answers as plain text, such as a container's log. A failure still comes back as a Status object.
    def text(path, query = {}) = json(Net::HTTP::Get, path, query, as: :text)

    # Follows a list from resource_version for at most timeout seconds, handing each event to the block as the API server
    # sends it: ADDED, MODIFIED, DELETED and BOOKMARK, each with the object and its resourceVersion. Bookmarks keep a
    # quiet list's version current, and the server sends one before the watch ends. A version older than the server
    # keeps raises Gone, said as a 410 answer or an ERROR event holding a Status with code 410. (Kubernetes API concepts,
    # Efficient detection of changes, Watch bookmarks and 410 Gone responses,
    # https://kubernetes.io/docs/reference/using-api/api-concepts/#efficient-detection-of-changes)
    def watch(path, resource_version:, timeout: WATCH_SECONDS, &)
      query = { "watch" => "true", "resourceVersion" => resource_version, "allowWatchBookmarks" => "true", "timeoutSeconds" => timeout }
      uri, request = request_for(Net::HTTP::Get, path, query)
      reaching do
        Http.request(uri, request, error_class: Error, read_timeout: timeout + WATCH_MARGIN, ipaddr: @ipaddr, cert_store: @store) do |response|
          refused!(response) unless response.code.to_i.between?(200, 299)
          stream(response, &)
        end
      end
    end

    def patch(path, body, type)
      raise ArgumentError, "Unknown patch type #{type}" unless PATCH_TYPES.include?(type)

      json(Net::HTTP::Patch, path, {}, body: body.to_json, type: type)
    end

    private

    def parse(server)
      uri = URI.parse(server.to_s.strip)
      raise Error, "The API server address must start with https://." unless uri.is_a?(URI::HTTPS)
      raise Error, "The API server address has no host." if uri.host.blank?
      raise Error, "The API server address cannot carry a user, a query or a fragment." if uri.userinfo || uri.query || uri.fragment

      uri.path = uri.path.to_s.delete_suffix("/")
      uri
    rescue URI::InvalidURIError
      raise Error, "The API server address could not be read."
    end

    def address(host)
      PublicAddress.check!(host, provider_key: PROVIDER_KEY).ip.to_s
    rescue PublicAddress::Refused => refused
      raise Error, refused.message
    end

    def json(verb, path, query, body: nil, type: nil, as: :json)
      uri, request = request_for(verb, path, query, body: body, type: type)
      reaching do
        Http.json(uri, request, error_class: Error, provider_name: PROVIDER_NAME, refine: ->(code, _) { REFINED[code] }, as: as,
                                read_timeout: READ_TIMEOUT, ipaddr: @ipaddr, cert_store: @store)
      end
    end

    def request_for(verb, path, query, body: nil, type: nil)
      uri = @root.dup
      uri.path = "#{@root.path}#{path}"
      uri.query = URI.encode_www_form(query.compact) if query.compact.any?
      request = verb.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request["Accept"] = "application/json, */*"
      if body
        request["Content-Type"] = type
        request.body = body
      end
      [ uri, request ]
    end

    # Each line of a watch is one event as JSON.
    def stream(response)
      buffer = +""
      handle = lambda do |line|
        next if line.strip.empty?

        event = JSON.parse(line)
        raise_status(event["object"].to_h) if event["type"] == WATCH_ERROR
        yield event
      end
      response.read_body do |chunk|
        buffer << chunk
        while (line = buffer.slice!(/\A[^\n]*\n/))
          handle.call(line)
        end
      end
      handle.call(buffer)
    rescue JSON::ParserError
      raise Error, "#{PROVIDER_NAME} sent a change that is not JSON."
    end

    def refused!(response)
      status = begin
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        {}
      end
      raise_status(status.is_a?(Hash) ? status.merge("code" => response.code.to_i) : { "code" => response.code.to_i })
    end

    def raise_status(status)
      code = status["code"].to_i
      said = Http.words(status["message"]) || "no reason given"
      message = "#{PROVIDER_NAME} answered #{code}: #{said}"
      raise Error.new(message).extend(RateLimited) if code == Http::TOO_MANY_REQUESTS

      raise REFINED.fetch(code, Error), message
    end

    # A refused token and a certificate that does not match say what to check, since the API server's own words do not.
    def reaching
      yield
    rescue Unauthorized => error
      raise Error, Sentence.all(error, "The cluster did not accept the token. It may have expired.")
    rescue Error => error
      raise unless error.message.include?(OpenSSL::SSL::SSLError.name)

      raise Error, Sentence.all(error, "The server's certificate is not signed by the CA certificate given, or does not name #{host}.")
    end
  end
end
