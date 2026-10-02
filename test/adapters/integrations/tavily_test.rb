require "test_helper"

module Integrations
  class TavilyTest < ActiveSupport::TestCase
    setup do
      ENV.stubs(:[]).returns(nil)
      ENV.stubs(:[]).with("TAVILY_API_KEY").returns("tvly-key")
    end

    test "a search asks for each page's text on Firefight's key" do
      Http.expects(:request).with do |uri, request, **|
        body = JSON.parse(request.body)
        uri.to_s == "https://api.tavily.com/search" && request["Authorization"] == "Bearer tvly-key" &&
          body == { "query" => "sidekiq retry", "max_results" => Tavily::MAX_RESULTS, "search_depth" => "basic", "include_raw_content" => "markdown" }
      end.returns(stub(code: "200", body: { results: [ { url: "https://x.dev" } ] }.to_json))

      assert_equal [ { "url" => "https://x.dev" } ], Tavily.search("sidekiq retry")
    end

    test "a refusal is raised with Tavily's reason, and a page it could not read says so" do
      Http.stubs(:request).returns(stub(code: "401", body: { detail: "Invalid API key" }.to_json))
      assert_equal "Tavily answered 401: Invalid API key", assert_raises(Tavily::Error) { Tavily.search("x") }.message

      Http.stubs(:request).returns(stub(code: "200", body: { results: [], failed_results: [ { url: "https://x.dev" } ] }.to_json))
      assert_match "could not read", assert_raises(Tavily::Error) { Tavily.read("https://x.dev") }.message
    end
  end
end
