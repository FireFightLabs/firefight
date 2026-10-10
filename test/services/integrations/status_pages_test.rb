require "test_helper"

class Integrations::StatusPagesTest < ActiveSupport::TestCase
  SUMMARY = {
    "page" => { "url" => "https://www.githubstatus.com" },
    "status" => { "indicator" => "major", "description" => "Partial System Outage" },
    "components" => [
      { "name" => "API Requests", "status" => "partial_outage", "group" => false },
      { "name" => "Git Operations", "status" => "operational", "group" => false },
      { "name" => "Everything", "status" => "major_outage", "group" => true }
    ],
    "incidents" => [ { "name" => "Elevated API errors", "status" => "investigating", "impact" => "major", "updated_at" => "2026-10-10T09:05:00Z",
                       "shortlink" => "https://stspg.io/abc", "incident_updates" => [ { "body" => "We are investigating   elevated errors." } ] } ],
    "scheduled_maintenances" => [ { "name" => "Database upgrade", "status" => "in_progress" }, { "name" => "Later", "status" => "scheduled" } ]
  }.freeze

  test "a Statuspage summary is read from the address the registry names and said with its incidents and what is not working" do
    Integrations::Http.expects(:json).with { |uri, request, **| uri.to_s == "https://www.githubstatus.com/api/v2/summary.json" && request["User-Agent"].present? }
                      .returns(SUMMARY.deep_dup)

    reading = Integrations::StatusPages.read(Upstream.find("github"))
    words = Integrations::StatusPages.words(reading)

    assert_equal Integrations::StatusPages::OUTAGE, reading.state
    assert reading.trouble?
    assert_match(/\AGitHub status, from https:\/\/www.githubstatus.com, read at \S+: Partial System Outage\.\nOpen incidents:\n/, words)
    assert_match "- Elevated API errors (investigating, major impact, updated 2026-10-10T09:05:00Z). We are investigating elevated errors. https://stspg.io/abc", words
    assert_match "Not fully working: API Requests (partial outage).", words
    assert_match "Maintenance under way: Database upgrade.", words
  end

  test "a page with nothing wrong says so" do
    Integrations::Http.stubs(:json).returns({ "status" => { "indicator" => "none", "description" => "All Systems Operational" }, "components" => [], "incidents" => [] })

    words = Integrations::StatusPages.words(Integrations::StatusPages.read(Upstream.find("github")))

    assert_match "All Systems Operational.\nNothing is reported wrong.", words
  end

  test "a page without a summary is read as a web page" do
    WebLookup.expects(:read).with("https://status.stripe.com").returns("https://status.stripe.com\nAPI: degraded performance")

    reading = Integrations::StatusPages.read(Upstream.find("stripe"))

    assert_equal Integrations::StatusPages::UNKNOWN, reading.state
    assert_match "Stripe status, from https://status.stripe.com, read at", Integrations::StatusPages.words(reading)
    assert_match "What the page says:\nhttps://status.stripe.com\nAPI: degraded performance", Integrations::StatusPages.words(reading)
  end
end
