require "test_helper"

class AlertProviders::OpsgenieTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "Opsgenie", provider: AlertSource::PROVIDER_OPSGENIE)
  end

  # Opsgenie's own example of an alert action its Webhook integration posts.
  def opsgenie_payload(action: "Create")
    {
      "source" => { "name" => "web", "type" => "API" },
      "alert" => {
        "updatedAt" => 1_420_452_193_166_002_000, "tags" => %w[tag1 tag2], "teams" => %w[team1 team2],
        "message" => " test alert", "username" => "fili@ifountain.com", "alertId" => "052652ac-5d1c-464a-812a-7dd18bbfba8c",
        "source" => "fili@ifountain.com", "alias" => "aliastest", "tinyId" => "23", "createdAt" => 1_420_452_191_104,
        "userId" => "daed1180-0ce8-438b-8f8e-57e1a5920a2d", "entity" => "", "priority" => "P2", "description" => "Disk is full"
      },
      "action" => action,
      "integrationId" => "37c8f316-17c6-49d7-899b-9c7e540c048d",
      "integrationName" => "Integration1"
    }
  end

  test "verifies the token the integration sends in its custom header" do
    assert AlertProviders::Opsgenie.verify(headers: { "X-Firefight-Token" => @source.secret_token }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Opsgenie.verify(headers: { "X-Firefight-Token" => "wrong" }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Opsgenie.verify(headers: {}, raw_body: "{}", source: @source)
  end

  test "a created alert fires, keyed on the alert, and a close resolves it" do
    created = AlertProviders::Opsgenie.normalize(opsgenie_payload, source: @source).sole[:fields]
    closed = AlertProviders::Opsgenie.normalize(opsgenie_payload(action: "Close"), source: @source).sole[:fields]

    assert_equal({ "external_id" => "052652ac-5d1c-464a-812a-7dd18bbfba8c", "fingerprint" => "052652ac-5d1c-464a-812a-7dd18bbfba8c",
                   "status" => Alert::STATUS_FIRING, "title" => "test alert", "description" => "Disk is full", "severity_raw" => "P2" }, created)
    assert_equal Alert::STATUS_RESOLVED, closed["status"]
    assert_equal created["fingerprint"], closed["fingerprint"]
  end

  test "an acknowledgement or a note is ignored, and a body that is not an alert action is not" do
    %w[Acknowledge AddNote Escalate].each do |action|
      assert_empty AlertProviders::Opsgenie.normalize(opsgenie_payload(action: action), source: @source)
      assert AlertProviders::Opsgenie.ignored?(opsgenie_payload(action: action))
    end
    assert_not AlertProviders::Opsgenie.ignored?({ "message" => "hello" })
  end
end
