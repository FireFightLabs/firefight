require "test_helper"

class AlertProviders::OpenstatusTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "OpenStatus", provider: AlertSource::PROVIDER_OPENSTATUS)
  end

  def fixture(name) = JSON.parse(file_fixture("alert_providers/openstatus_#{name}.json").read)

  test "accepts the token in the channel's custom header" do
    assert AlertProviders::Openstatus.verify(headers: { "X-Firefight-Token" => @source.secret_token }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Openstatus.verify(headers: { "X-Firefight-Token" => "wrong" }, raw_body: "{}", source: @source)
  end

  test "an error fires on the monitor and a recovery resolves it" do
    error = AlertProviders::Openstatus.normalize(fixture("alert"), source: @source).sole[:fields]
    recovered = AlertProviders::Openstatus.normalize(fixture("recovery"), source: @source).sole[:fields]

    assert_equal({ "external_id" => "1:error:1744023705307", "fingerprint" => "monitor:1", "status" => Alert::STATUS_FIRING,
                   "title" => "test is failing", "service" => "test", "severity_raw" => "error",
                   "description" => "Internal Server Error. Status code 500. Latency 1337 ms. http://openstat.us" }, error)
    assert_equal Alert::STATUS_RESOLVED, recovered["status"]
    assert_equal error["fingerprint"], recovered["fingerprint"]
  end

  test "a body that is not a monitor check is unrecognized" do
    assert_empty AlertProviders::Openstatus.normalize({ "status" => "error" }, source: @source)
  end
end
