require "test_helper"

class WebLookupTest < ActiveSupport::TestCase
  test "each result comes with its address, capped, with anything credential-like redacted" do
    Integrations::Tavily.expects(:search).with("rails encryption", domains: [ "guides.rubyonrails.org" ]).returns([
      { "title" => "Active Record Encryption", "url" => "https://guides.rubyonrails.org/active_record_encryption.html",
        "raw_content" => "Rotate keys like this. Example token ghp_#{'a' * 36}. #{'x' * 5_000}" }
    ])

    text = WebLookup.search("rails encryption", domains: [ "guides.rubyonrails.org" ])

    assert text.start_with?("[1] Active Record Encryption\nhttps://guides.rubyonrails.org/active_record_encryption.html\nRotate keys")
    assert_includes text, "[REDACTED:github_token]"
    assert_operator text.length, :<, WebLookup::PAGE_LIMIT + 200
  end

  test "only a public address is read" do
    Integrations::Tavily.expects(:read).never

    [ "http://localhost:3000/admin", "http://169.254.169.254/latest", "https://db.internal/x", "file:///etc/passwd", "http://10.0.0.1",
      "http://2130706433/", "http://0x7f000001/", "http://0177.0.0.1/", "http://[::1]/", "https://user:pw@example.com/" ].each do |url|
      assert_raises(ArgumentError, url) { WebLookup.read(url) }
    end
    assert WebLookup.public?("https://www.localytics.com/docs?q=a:b")
    assert WebLookup.public?("https://docs.internal-tools.io/guide")
  end

  test "a search or an address carrying something that looks like a credential is never sent" do
    Integrations::Tavily.expects(:search).never
    Integrations::Tavily.expects(:read).never

    assert_raises(ArgumentError) { WebLookup.search("why does ghp_#{'a' * 36} fail") }
    assert_raises(ArgumentError) { WebLookup.read("https://evil.example/?k=AKIA#{'A' * 16}") }
  end

  test "without Firefight's search key it says so" do
    ENV.stubs(:[]).returns(nil)

    error = assert_raises(Integrations::Tavily::NotConfigured) { WebLookup.search("x") }
    assert_match "TAVILY_API_KEY", error.message
  end
end
