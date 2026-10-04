module Integrations
  # What the coding agents' APIs share: JSON over HTTPS with the workspace's own key, and a refusal said in the
  # provider's own words. Each subclass knows its paths and where its errors keep their reason.
  class CodingAgentApi
    class Error < Integrations::Error
      attr_reader :status

      def initialize(message = nil, status: nil)
        super(message)
        @status = status
      end
    end

    # Asked too often, so a caller following a session waits longer rather than give up.
    class RateLimited < Error; end

    TOO_MANY_REQUESTS = 429
    VERBS = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.freeze

    def initialize(key)
      @key = key
    end

    private

    def call(verb, path, body: nil, query: {})
      uri = URI.parse("#{root}#{path}")
      uri.query = URI.encode_www_form(query.compact) if query.compact.any?
      request = VERBS.fetch(verb).new(uri)
      request["Authorization"] = "Bearer #{@key}"
      request["Accept"] = "application/json"
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      response = Http.request(uri, request, error_class: Error, read_timeout: 30)
      parsed = parse(response.body)
      return parsed if response.code.to_i.between?(200, 299)

      error = response.code.to_i == TOO_MANY_REQUESTS ? RateLimited : Error
      raise error.new("#{self.class::NAME} answered #{response.code}: #{reason(parsed) || 'no reason given'}", status: response.code.to_i)
    end

    # A body that is not JSON carries nothing to read, and a change that went through stays one that went through.
    def parse(body)
      parsed = body.to_s.strip.empty? ? {} : JSON.parse(body)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    # Where the API is. A provider with several deployments says which one the connection reaches.
    def root = self.class::ROOT

    def segment(value) = ERB::Util.url_encode(value.to_s)
  end
end
