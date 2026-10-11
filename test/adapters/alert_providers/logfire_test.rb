require "test_helper"

class AlertProviders::LogfireTest < ActiveSupport::TestCase
  ALERT_ID = "0198b2c4-5d1e-7a3f-9c2b-1e4f6a8d0c3b".freeze

  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "Logfire", provider: AlertSource::PROVIDER_LOGFIRE)
  end

  def fixture(name) = JSON.parse(file_fixture("alert_providers/logfire_#{name}.json").read)

  def fields(payload) = AlertProviders::Logfire.normalize(payload, source: @source).sole[:fields]

  test "accepts only the secret taken out of the address, never one sent as a header" do
    assert AlertProviders::Logfire.verify(headers: { AlertAddressSecret::ENV_KEY => @source.secret_token }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Logfire.verify(headers: { AlertAddressSecret::ENV_KEY => "wrong" }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Logfire.verify(headers: {}, raw_body: "{}", source: @source)
    assert_not AlertProviders::Logfire.verify(headers: { "Authorization" => "Bearer #{@source.secret_token}", "X-Firefight-Token" => @source.secret_token },
                                              raw_body: "{}", source: @source)
  end

  test "rows fire, keyed on the alert, with the run as the delivery and the alert's page as its link" do
    firing = fields(fixture("alert"))

    assert_equal Alert::STATUS_FIRING, firing["status"]
    assert_equal "alert:#{ALERT_ID}", firing["fingerprint"]
    assert_equal "run:0198b2c9-11aa-7d42-8e5f-3c6b9a2d4e10", firing["external_id"]
    assert_equal "Example alert", firing["title"]
    assert_equal "Example description\nThe query returned 1 row.", firing["description"]
    assert_equal "acme-qa", firing["service"]
    assert_equal fixture("alert").dig("links", "alert"), firing["url"]
  end

  test "no rows resolve the same alert" do
    resolved = fields(fixture("alert_resolved"))

    assert_equal Alert::STATUS_RESOLVED, resolved["status"]
    assert_equal "alert:#{ALERT_ID}", resolved["fingerprint"]
    assert_equal "Example description", resolved["description"]
  end

  test "a query Logfire could not run fires with its errors" do
    payload = fixture("alert_resolved").merge("errors" => [ "column canary does not exist" ])

    errored = fields(payload)
    assert_equal Alert::STATUS_FIRING, errored["status"]
    assert_includes errored["description"], "Logfire could not run the query. [\"column canary does not exist\"]"
  end

  test "without a link the alert is keyed on its project and name" do
    payload = fixture("alert").except("links")

    keyed = fields(payload)
    assert_equal "alert:acme-qa:Example alert", keyed["fingerprint"]
    assert_equal "alert:acme-qa:Example alert:2026-08-02T21:00:45.204370Z", keyed["external_id"]
    assert_nil keyed["url"]
  end

  test "a link that is not an address still keys the alert on its id" do
    payload = fixture("alert")
    payload["links"]["alert"] = "https://logfire-eu.pydantic.dev/acme/acme-qa/alerts/#{ALERT_ID}?alertRunId=a b|c"

    assert_equal "alert:#{ALERT_ID}", fields(payload)["fingerprint"]
  end

  test "a body that is not a Logfire alert is not recognized" do
    assert_empty AlertProviders::Logfire.normalize({ "text" => "hello" }, source: @source)
    assert_empty AlertProviders::Logfire.normalize(fixture("alert").merge("n_rows" => "1"), source: @source)
  end
end
