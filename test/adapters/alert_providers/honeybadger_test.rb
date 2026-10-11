require "test_helper"

class AlertProviders::HoneybadgerTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "Honeybadger", provider: AlertSource::PROVIDER_HONEYBADGER)
  end

  def fields_for(name) = AlertProviders::Honeybadger.normalize(fixture(name), source: @source).sole[:fields]
  def fixture(name) = JSON.parse(file_fixture("alert_providers/honeybadger_#{name}.json").read)

  test "accepts the bearer token set on the integration" do
    assert AlertProviders::Honeybadger.verify(headers: { "Authorization" => "Bearer #{@source.secret_token}" }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Honeybadger.verify(headers: { "Honeybadger-Token" => @source.secret_token }, raw_body: "{}", source: @source)
  end

  test "an error fires on the fault, linking to the notice, and its resolve reaches the same alert" do
    occurred = fields_for("occurred")
    resolved = fields_for("resolved")

    assert_equal "fault:101337516", occurred["fingerprint"]
    assert_equal Alert::STATUS_FIRING, occurred["status"]
    assert occurred["title"].start_with?("ActiveRecord::NoDatabaseError: We could not find your database")
    assert_equal "production", occurred["environment"]
    assert_equal "Testy McTestFace", occurred["service"]
    assert_equal "https://app.honeybadger.io/projects/123321/faults/101337516/01HCN3JWWXRQX511BB83WM2X95", occurred["url"]
    assert_equal Alert::STATUS_RESOLVED, resolved["status"]
    assert_equal occurred["fingerprint"], resolved["fingerprint"]
  end

  test "an uptime check fires when down and resolves when up, keyed on the site" do
    down = fields_for("down")
    up = fields_for("up")

    assert_equal "site:c42c4c0a-6e3d-4303-9769-549ed2a5818e", down["fingerprint"]
    assert_equal "Heroku is down", down["title"]
    assert_equal Alert::STATUS_RESOLVED, up["status"]
    assert_equal down["fingerprint"], up["fingerprint"]
  end

  test "a missing check in fires and resolves when it reports again" do
    assert_equal Alert::STATUS_FIRING, fields_for("check_in_missing")["status"]
    assert_equal Alert::STATUS_RESOLVED, fields_for("check_in_reporting")["status"]
    assert_equal "check_in:XYZLOL", fields_for("check_in_reporting")["fingerprint"]
  end

  test "an assignment is accepted and ignored" do
    assert_empty AlertProviders::Honeybadger.normalize(fixture("assigned"), source: @source)
    assert AlertProviders::Honeybadger.ignored?(fixture("assigned"))
    assert_not AlertProviders::Honeybadger.ignored?(fixture("occurred"))
  end
end
