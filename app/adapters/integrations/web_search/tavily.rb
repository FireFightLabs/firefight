module Integrations
  module WebSearch
    # Tavily's search and extract API. A search returns each page's cleaned text in the same call.
    class Tavily
      API_ROOT = "https://api.tavily.com".freeze
      READ_TIMEOUT = 30

      def name = PROVIDER_TAVILY

      def configured? = key.present?

      def search(query, domains: [])
        body = { query: query, max_results: MAX_RESULTS, search_depth: "basic", include_raw_content: "markdown",
                 include_domains: domains.presence }.compact
        Array(post("/search", body)["results"]).map do |result|
          Result.new(title: result["title"].to_s, url: result["url"].to_s, text: (result["raw_content"].presence || result["content"]).to_s)
        end
      end

      def read(url)
        found = Array(post("/extract", { urls: [ url ], format: "markdown" })["results"]).first
        raise Error, "Tavily could not read #{url}." unless found

        Page.new(url: found["url"].presence || url, text: found["raw_content"].to_s)
      end

      private

      def key = ENV["TAVILY_API_KEY"].presence

      def post(path, body)
        uri = URI.parse("#{API_ROOT}#{path}")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{key}"
        request["Content-Type"] = "application/json"
        request.body = body.to_json
        response = Http.request(uri, request, error_class: Error, read_timeout: READ_TIMEOUT)
        parsed = JSON.parse(response.body.to_s.presence || "{}")
        return parsed if response.code.to_i.between?(200, 299)

        raised = REFUSED_CODES.include?(response.code.to_i) ? Refused : Error
        raise raised, "Tavily answered #{response.code}: #{parsed['detail'] || parsed['error'] || 'no reason given'}"
      rescue JSON::ParserError
        raise Error, "Tavily answered #{response&.code} with something that is not JSON"
      end
    end
  end
end
