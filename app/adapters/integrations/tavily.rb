module Integrations
  # Tavily's search and extract API, on Firefight's own key, which is how Halon and a coding agent read the public web.
  class Tavily
    class Error < Integrations::Error; end
    class NotConfigured < Error; end

    API_ROOT = "https://api.tavily.com".freeze
    MAX_RESULTS = 8
    READ_TIMEOUT = 30

    def self.configured? = key.present?

    def self.key = ENV["TAVILY_API_KEY"].presence

    # Results with each page's cleaned text, so one call answers most questions.
    def self.search(query, domains: [])
      body = { query: query, max_results: MAX_RESULTS, search_depth: "basic", include_raw_content: "markdown",
               include_domains: domains.presence }.compact
      Array(post("/search", body)["results"])
    end

    # One page's text, for a page a search or the agent already knows.
    def self.read(url)
      answer = post("/extract", { urls: [ url ], format: "markdown" })
      found = Array(answer["results"]).first
      raise Error, "Tavily could not read #{url}." unless found

      found
    end

    def self.post(path, body)
      raise NotConfigured, "Web search is not set up on this Firefight (TAVILY_API_KEY)." unless configured?

      uri = URI.parse("#{API_ROOT}#{path}")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{key}"
      request["Content-Type"] = "application/json"
      request.body = body.to_json
      response = Http.request(uri, request, error_class: Error, read_timeout: READ_TIMEOUT)
      parsed = JSON.parse(response.body.to_s.presence || "{}")
      return parsed if response.code.to_i.between?(200, 299)

      raise Error, "Tavily answered #{response.code}: #{parsed['detail'] || parsed['error'] || 'no reason given'}"
    rescue JSON::ParserError
      raise Error, "Tavily answered #{response&.code} with something that is not JSON"
    end
    private_class_method :post
  end
end
