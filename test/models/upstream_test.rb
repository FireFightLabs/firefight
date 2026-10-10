require "test_helper"

class UpstreamTest < ActiveSupport::TestCase
  test "the registry holds the providers Firefight connects and the outside systems it does not, each key once" do
    keys = Upstream.all.map(&:key)

    assert_equal keys.uniq, keys
    assert Upstream.find("github").connectable?
    assert_not Upstream.find("stripe").connectable?
    Upstream.all.each do |entry|
      assert entry.hosts.all? { |host| host.match?(/\A[a-z0-9.-]+\.[a-z]{2,}\z/) }, "#{entry.key}'s hosts are domain names"
      assert entry.setting_words.all? { |word| word.match?(/\A[A-Z][A-Z0-9]+\z/) }, "#{entry.key}'s setting words are whole words in capitals"
    end
  end

  test "every status page is an https page read as a Statuspage summary or as a page" do
    pages = Upstream.all.filter_map(&:status_page)

    assert pages.size > 40
    assert pages.all? { |page| page.url.start_with?("https://") && Upstream::FEEDS.include?(page.feed) }
    assert_equal "https://www.githubstatus.com/api/v2/summary.json", Upstream.find("github").status_page.summary_url
    assert_raises(ArgumentError) { Upstream::StatusPage.new(url: "https://status.example.com", feed: "rss") }
  end

  test "a host belongs to the system naming the most specific of its domains" do
    assert_equal "Auth0", Upstream.for_host("acme.eu.auth0.com").name
    assert_equal "Stripe", Upstream.for_host("API.STRIPE.COM.").name
    assert_nil Upstream.for_host("stripe.com.evil.example")
    assert_nil Upstream.for_host("")
  end

  test "a provider is found by its key, its name or one of the names it goes by" do
    assert_equal "stripe", Upstream.named("Stripe").key
    assert_equal "paypal", Upstream.named("braintree").key
    assert_nil Upstream.named("nobody")
  end

  test "only failing lines point at a provider, most named first, by the host they named" do
    text = <<~LOGS
      INFO GET https://api.stripe.com/v1/charges 200
      ERROR Net::ReadTimeout calling https://api.stripe.com/v1/charges
      ERROR connect ECONNREFUSED api.stripe.com:443
      WARN request to api.github.com failed with 503
      INFO all good at example.org
    LOGS

    pointed = Upstream.pointed_at(text)

    assert_equal [ [ "Stripe", "api.stripe.com", 2 ], [ "GitHub", "api.github.com", 1 ] ], pointed.map { |found| [ found.entry.name, found.host, found.lines ] }
    assert_empty Upstream.pointed_at("INFO GET https://api.stripe.com/v1/charges 200")
  end

  test "a setting named for an outside system is kept on the map by its name" do
    assert_equal [ "Stripe" ], Upstream.for_setting("STRIPE_SECRET_KEY").map(&:name)
    assert ResourceMap::Use.named("web", "STRIPE_SECRET_KEY")
    assert_nil ResourceMap::Use.named("web", "FEATURE_SECRET_KEY")
  end
end
