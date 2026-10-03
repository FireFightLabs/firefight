require "test_helper"

module Integrations
  class WebSearchTest < ActiveSupport::TestCase
    setup do
      ENV.stubs(:[]).returns(nil)
      @found = [ WebSearch::Result.new(title: "Docs", url: "https://x.dev", text: "text") ]
    end

    test "the first provider in the order with a key answers, Tavily first when nothing is set" do
      keys(tavily: true, firecrawl: true)
      WebSearch::Tavily.any_instance.expects(:search).returns(@found)
      WebSearch::Firecrawl.any_instance.expects(:search).never

      assert_equal @found, WebSearch.search("x")
    end

    test "the order is a setting, separately for searching and reading, and a provider without a key is passed over" do
      keys(tavily: true, firecrawl: true)
      ENV.stubs(:[]).with("WEB_SEARCH_PROVIDERS").returns("firecrawl, tavily")
      ENV.stubs(:[]).with("WEB_READ_PROVIDERS").returns("tavily")
      WebSearch::Firecrawl.any_instance.expects(:search).returns(@found)
      page = WebSearch::Page.new(url: "https://x.dev", text: "text")
      WebSearch::Tavily.any_instance.expects(:read).returns(page)

      assert_equal @found, WebSearch.search("x")
      assert_equal page, WebSearch.read("https://x.dev")

      keys(tavily: false, firecrawl: true)
      WebSearch::Firecrawl.any_instance.expects(:read).returns(page)
      ENV.stubs(:[]).with("WEB_READ_PROVIDERS").returns("tavily,firecrawl")
      assert_equal page, WebSearch.read("https://x.dev")
    end

    test "a provider that fails hands over to the next, and the last one's failure is what is said" do
      keys(tavily: true, firecrawl: true)
      WebSearch::Tavily.any_instance.expects(:search).raises(WebSearch::Error, "Tavily answered 500: down")
      WebSearch::Firecrawl.any_instance.expects(:search).returns(@found)
      assert_equal @found, WebSearch.search("x")

      WebSearch::Tavily.any_instance.stubs(:search).raises(WebSearch::Error, "Tavily answered 500: down")
      WebSearch::Firecrawl.any_instance.stubs(:search).raises(WebSearch::Error, "Firecrawl answered 402: Insufficient credits")
      assert_equal "Firecrawl answered 402: Insufficient credits", assert_raises(WebSearch::Error) { WebSearch.search("x") }.message
    end

    test "no key says so, and an order naming an unknown provider is refused" do
      keys(tavily: false, firecrawl: false)
      assert_equal WebSearch::NOT_CONFIGURED, assert_raises(WebSearch::NotConfigured) { WebSearch.search("x") }.message

      ENV.stubs(:[]).with("WEB_SEARCH_PROVIDERS").returns("tavily,bing")
      assert_match "bing", assert_raises(WebSearch::Error) { WebSearch.search("x") }.message
    end

    test "reading falls back too, and the answer says which provider gave it and that it was a fallback" do
      keys(tavily: true, firecrawl: true)
      page = WebSearch::Page.new(url: "https://x.dev", text: "text")
      WebSearch::Tavily.any_instance.expects(:read).raises(WebSearch::Error, "Tavily could not read https://x.dev.")
      WebSearch::Firecrawl.any_instance.expects(:read).returns(page)
      Rails.logger.expects(:info).with { |line| JSON.parse(line) == { "event" => "web_lookup.answered", "provider" => "firecrawl", "fallback" => true } }

      assert_equal page, WebSearch.read("https://x.dev")
    end

    test "a provider turning down what was asked is not handed to the next, and no new provider starts once the lookup has run long" do
      keys(tavily: true, firecrawl: true)
      WebSearch::Tavily.any_instance.expects(:search).raises(WebSearch::Refused, "Tavily answered 400: bad query")
      WebSearch::Firecrawl.any_instance.expects(:search).never
      assert_raises(WebSearch::Refused) { WebSearch.search("x") }

      WebSearch::Tavily.any_instance.unstub(:search)
      WebSearch::Tavily.any_instance.expects(:search).with { travel(WebSearch::FALLBACK_WITHIN + 1.second) || true }.raises(WebSearch::Error, "timed out")
      assert_equal "timed out", assert_raises(WebSearch::Error) { WebSearch.search("x") }.message
    end

    test "a provider named twice is asked once" do
      keys(tavily: true, firecrawl: false)
      ENV.stubs(:[]).with("WEB_SEARCH_PROVIDERS").returns("tavily,tavily")
      WebSearch::Tavily.any_instance.expects(:search).once.raises(WebSearch::Error, "down")

      assert_raises(WebSearch::Error) { WebSearch.search("x") }
    end

    private

    def keys(tavily:, firecrawl:)
      ENV.stubs(:[]).with("TAVILY_API_KEY").returns(tavily ? "tvly" : nil)
      ENV.stubs(:[]).with("FIRECRAWL_API_KEY").returns(firecrawl ? "fc" : nil)
    end
  end
end
