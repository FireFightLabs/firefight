module Integrations
  # What the coding agents' APIs share: JSON over HTTPS with the workspace's own key. A refusal is raised in the
  # provider's own words as the class its status names, so a pack can say what to change.
  class CodingAgentApi
    class Error < Integrations::Error; end
    class Unauthorized < Error; end
    class Forbidden < Error; end
    class NotFound < Error
      include Integrations::NotFound
    end

    REFUSALS = { 401 => Unauthorized, 403 => Forbidden, 404 => NotFound }.freeze
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
      answer = Http.json(uri, request, error_class: Error, provider_name: self.class::NAME, refine: ->(code, _said) { REFUSALS[code] })
      answer.is_a?(Hash) ? answer : {}
    end

    # Where the API is. A provider with several deployments says which one the connection reaches.
    def root = self.class::ROOT

    def segment(value) = Http.segment(value)
  end
end
