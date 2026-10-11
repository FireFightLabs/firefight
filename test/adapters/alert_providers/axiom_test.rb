require "test_helper"

class AlertProviders::AxiomTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "Axiom", provider: AlertSource::PROVIDER_AXIOM)
  end

  def fixture(name) = JSON.parse(file_fixture("alert_providers/axiom_#{name}.json").read)

  test "accepts the token in the notifier's header" do
    assert AlertProviders::Axiom.verify(headers: { "X-Firefight-Token" => @source.secret_token }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Axiom.verify(headers: {}, raw_body: "{}", source: @source)
  end

  test "an opened monitor fires and its close resolves the same alert" do
    opened = AlertProviders::Axiom.normalize(fixture("monitor"), source: @source).sole[:fields]
    closed = AlertProviders::Axiom.normalize(fixture("monitor_resolved"), source: @source).sole[:fields]

    assert_equal "monitor:CabI3w142069etTgd0", opened["fingerprint"]
    assert_equal "Axiom Monitor Test Triggered", opened["title"]
    assert_equal "Current value of 57347 is above or equal to the threshold value of 0", opened["description"]
    assert_equal Alert::STATUS_RESOLVED, closed["status"]
    assert_equal opened["fingerprint"], closed["fingerprint"]
  end

  test "a monitor that notifies by group keys each group apart" do
    payload = fixture("monitor")
    payload["event"].merge!("groupKeys" => [ "service" ], "groupValues" => [ "checkout" ])

    assert_equal "monitor:CabI3w142069etTgd0:checkout", AlertProviders::Axiom.normalize(payload, source: @source).sole[:fields]["fingerprint"]
  end
end
