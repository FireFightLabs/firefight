require "test_helper"

class DocsClientTest < ActiveSupport::TestCase
  test "robots.txt keeps the reader off what its group disallows, the longest rule deciding" do
    robots = DocsClient::Robots.parse(<<~TEXT)
      User-agent: Googlebot
      Disallow: /

      User-agent: *
      Disallow: /*/raw
      Allow: /docs/raw-guide$
      Crawl-delay: 2
    TEXT

    assert_nothing_raised { robots.check!(URI("https://example.com/docs/page.md")) }
    assert_nothing_raised { robots.check!(URI("https://example.com/docs/raw-guide")) }
    assert_raises(DocsClient::Refused) { robots.check!(URI("https://example.com/org/repo/-/raw/main/doc.md")) }
    assert_equal 2.0, robots.delay
  end

  test "a group naming this reader wins over the one for every reader, and a site that says no AI input is never read" do
    named = DocsClient::Robots.parse("User-agent: *\nDisallow: /\n\nUser-agent: FirefightDocs\nAllow: /\n")
    assert_nothing_raised { named.check!(URI("https://example.com/docs")) }

    refused = DocsClient::Robots.parse("User-agent: *\nContent-Signal: ai-train=no, search=yes, ai-input=no\nAllow: /\n")
    assert_match "may not be an AI's input", assert_raises(DocsClient::Refused) { refused.check!(URI("https://example.com/docs")) }.message
  end

  test "a site with no robots.txt is read, saying who is reading, and a page that did not change answers no body" do
    requests = []
    responses = { "/robots.txt" => response(404, ""), "/docs/a.md" => response(304, "") }
    DocsClient.any_instance.stubs(:sleep)
    DocsClient.any_instance.stubs(:transport).with do |_uri, request|
      requests << request
      true
    end.returns(*responses.values)

    answer = DocsClient.new.page("https://example.com/docs/a.md", revision: "\"v1\"")

    assert_nil answer.body
    assert_equal "\"v1\"", answer.revision
    assert_equal DocsClient::USER_AGENT, requests.last["User-Agent"]
    assert_equal "\"v1\"", requests.last["If-None-Match"]
  end

  private

  def response(code, body)
    klass = Net::HTTPResponse::CODE_TO_OBJ.fetch(code.to_s)
    klass.new("1.1", code.to_s, "").tap do |made|
      made.instance_variable_set(:@read, true)
      made.instance_variable_set(:@body, body)
    end
  end
end
