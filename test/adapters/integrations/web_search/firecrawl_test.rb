require "test_helper"

module Integrations
  module WebSearch
    class FirecrawlTest < ActiveSupport::TestCase
      setup do
        ENV.stubs(:[]).returns(nil)
        ENV.stubs(:[]).with("FIRECRAWL_API_KEY").returns("fc-key")
        @firecrawl = Firecrawl.new
      end

      test "a search scrapes each result to markdown, only on the domains asked, and answers the shared shape" do
        Http.expects(:request).with do |uri, request, **|
          body = JSON.parse(request.body)
          uri.to_s == "https://api.firecrawl.dev/v2/search" && request["Authorization"] == "Bearer fc-key" &&
            body == { "query" => "sidekiq retry", "limit" => MAX_RESULTS, "includeDomains" => [ "sidekiq.org" ], "timeout" => Firecrawl::SCRAPE_TIMEOUT_MS,
                      "scrapeOptions" => { "formats" => [ { "type" => "markdown" } ], "onlyMainContent" => true } }
        end.returns(stub(code: "200", body: { success: true, data: { web: [
          { title: "Retries", url: "https://sidekiq.org/retries", description: "short", markdown: "full" },
          { title: "Not scraped", url: "https://sidekiq.org/x", description: "only a snippet", markdown: nil }
        ] } }.to_json))

        assert_equal [ Result.new(title: "Retries", url: "https://sidekiq.org/retries", text: "full"),
                       Result.new(title: "Not scraped", url: "https://sidekiq.org/x", text: "only a snippet") ],
                     @firecrawl.search("sidekiq retry", domains: [ "sidekiq.org" ])
      end

      test "a page is read to markdown with where it ended up, and a failure carries Firecrawl's reason" do
        Http.stubs(:request).returns(stub(code: "200", body: { success: true, data: { markdown: "# Docs", metadata: { url: "https://x.dev/docs/", sourceURL: "https://x.dev/docs" } } }.to_json))
        assert_equal Page.new(url: "https://x.dev/docs/", text: "# Docs"), @firecrawl.read("https://x.dev/docs")

        Http.stubs(:request).returns(stub(code: "402", body: { success: false, error: "Insufficient credits" }.to_json))
        assert_equal "Firecrawl answered 402: Insufficient credits", assert_raises(Error) { @firecrawl.read("https://x.dev") }.message

        Http.stubs(:request).returns(stub(code: "400", body: { success: false, error: "Bad request" }.to_json))
        assert_raises(Refused) { @firecrawl.read("https://x.dev") }
      end
    end
  end
end
