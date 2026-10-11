require "test_helper"

class AlertProviders::BetterStackTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "Better Stack", provider: AlertSource::PROVIDER_BETTER_STACK)
  end

  def fixture(name) = JSON.parse(file_fixture("alert_providers/#{name}.json").read)

  test "accepts the token in the webhook's custom header or as its Basic auth password" do
    basic = "Basic #{Base64.strict_encode64("firefight:#{@source.secret_token}")}"

    assert AlertProviders::BetterStack.verify(headers: { "X-Firefight-Token" => @source.secret_token }, raw_body: "{}", source: @source)
    assert AlertProviders::BetterStack.verify(headers: { "Authorization" => basic }, raw_body: "{}", source: @source)
    assert_not AlertProviders::BetterStack.verify(headers: { "X-Firefight-Token" => "wrong" }, raw_body: "{}", source: @source)
  end

  test "a started incident fires and its resolve reaches the same alert" do
    started = AlertProviders::BetterStack.normalize(fixture("betterstack_started"), source: @source).sole[:fields]
    resolved = AlertProviders::BetterStack.normalize(fixture("betterstack_resolved"), source: @source).sole[:fields]

    assert_equal({ "external_id" => "1:2020-10-21T10:51:28.151Z", "fingerprint" => "incident:1", "status" => Alert::STATUS_FIRING,
                   "title" => "Tesla.com homepage", "description" => "Error 500. https://tesla.com" }, started)
    assert_equal Alert::STATUS_RESOLVED, resolved["status"]
    assert_equal started["fingerprint"], resolved["fingerprint"]
  end

  test "a comment is accepted and ignored" do
    comment = fixture("betterstack_comment")

    assert_empty AlertProviders::BetterStack.normalize(comment, source: @source)
    assert AlertProviders::BetterStack.ignored?(comment)
    assert_not AlertProviders::BetterStack.ignored?({ "data" => "nope" })
  end
end
