require "test_helper"

module Integrations
  module WebSearch
    class TavilyTest < ActiveSupport::TestCase
      setup do
        ENV.stubs(:[]).returns(nil)
        ENV.stubs(:[]).with("TAVILY_API_KEY").returns("tvly-key")
        @tavily = Tavily.new
      end

      test "a search asks for each page's text on Firefight's key and answers the shared shape" do
        Http.expects(:request).with do |uri, request, **|
          body = JSON.parse(request.body)
          uri.to_s == "https://api.tavily.com/search" && request["Authorization"] == "Bearer tvly-key" &&
            body == { "query" => "sidekiq retry", "max_results" => MAX_RESULTS, "search_depth" => "basic", "include_raw_content" => "markdown" }
        end.returns(stub(code: "200", body: { results: [ { title: "Retries", url: "https://x.dev", content: "short", raw_content: "full" } ] }.to_json))

        assert_equal [ Result.new(title: "Retries", url: "https://x.dev", text: "full") ], @tavily.search("sidekiq retry")
      end

      test "a refusal is raised with Tavily's reason, and a page it could not read says so" do
        Http.stubs(:request).returns(stub(code: "401", body: { detail: "Invalid API key" }.to_json))
        assert_equal "Tavily answered 401: Invalid API key", assert_raises(Error) { @tavily.search("x") }.message

        Http.stubs(:request).returns(stub(code: "200", body: { results: [], failed_results: [ { url: "https://x.dev" } ] }.to_json))
        assert_match "could not read", assert_raises(Error) { @tavily.read("https://x.dev") }.message
      end
    end
  end
end
