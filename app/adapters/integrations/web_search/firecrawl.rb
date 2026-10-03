module Integrations
  module WebSearch
    # Firecrawl's search and scrape API. A search scrapes each result to markdown in the same call, and a page is read
    # in a browser, so a page that only draws its text with JavaScript is read too.
    class Firecrawl
      API_ROOT = "https://api.firecrawl.dev/v2".freeze
      READ_TIMEOUT = 45
      # Firecrawl's own limit, in milliseconds, kept under ours so it answers before we give up on it.
      SCRAPE_TIMEOUT_MS = 40_000

      def name = PROVIDER_FIRECRAWL

      def configured? = key.present?

      def search(query, domains: [])
        body = { query: query, limit: MAX_RESULTS, includeDomains: domains.presence, timeout: SCRAPE_TIMEOUT_MS,
                 scrapeOptions: { formats: [ { type: "markdown" } ], onlyMainContent: true } }.compact
        Array(post("/search", body).dig("data", "web")).map do |result|
          Result.new(title: result["title"].to_s, url: result["url"].to_s, text: (result["markdown"].presence || result["description"]).to_s)
        end
      end

      def read(url)
        page = post("/scrape", { url: url, formats: [ "markdown" ], onlyMainContent: true, timeout: SCRAPE_TIMEOUT_MS })["data"]
        raise Error, "Firecrawl could not read #{url}." if page.blank? || page["markdown"].blank?

        Page.new(url: page.dig("metadata", "url").presence || page.dig("metadata", "sourceURL").presence || url, text: page["markdown"].to_s)
      end

      private

      def key = ENV["FIRECRAWL_API_KEY"].presence

      def post(path, body)
        uri = URI.parse("#{API_ROOT}#{path}")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{key}"
        request["Content-Type"] = "application/json"
        request.body = body.to_json
        response = Http.request(uri, request, error_class: Error, read_timeout: READ_TIMEOUT)
        parsed = JSON.parse(response.body.to_s.presence || "{}")
        return parsed if response.code.to_i.between?(200, 299) && parsed["success"] != false

        raised = REFUSED_CODES.include?(response.code.to_i) ? Refused : Error
        raise raised, "Firecrawl answered #{response.code}: #{parsed['error'] || 'no reason given'}"
      rescue JSON::ParserError
        raise Error, "Firecrawl answered #{response&.code} with something that is not JSON"
      end
    end
  end
end
