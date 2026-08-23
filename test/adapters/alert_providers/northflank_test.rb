require "test_helper"

class AlertProviders::NorthflankTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(
      workspace: workspaces(:slack_workspace_one),
      name: "Northflank prod",
      provider: AlertSource::PROVIDER_NORTHFLANK
    )
  end

  def northflank_payload(event: "container:crash")
    {
      "event" => event,
      "data" => {
        "service" => { "id" => "website", "name" => "Website" },
        "project" => { "id" => "personal-blog", "name" => "Personal Blog" }
      }
    }
  end

  test "verifies the Northflank token header" do
    headers = { AlertProviders::Northflank::TOKEN_HEADER => @source.secret_token }
    assert AlertProviders::Northflank.verify(headers: headers, raw_body: "{}", source: @source)

    assert_not AlertProviders::Northflank.verify(
      headers: { AlertProviders::Northflank::TOKEN_HEADER => "wrong" }, raw_body: "{}", source: @source
    )
    assert_not AlertProviders::Northflank.verify(headers: {}, raw_body: "{}", source: @source)
  end

  test "normalizes event payloads with service, title and stable fingerprint" do
    item = AlertProviders::Northflank.normalize(northflank_payload, source: @source).first
    fields = item[:fields]

    assert_equal northflank_payload, item[:payload]

    assert_equal "container:crash", fields["event"]
    assert_equal "website", fields["service"]
    assert_equal "Container crash: Website (Personal Blog)", fields["title"]
    assert_equal Alert::STATUS_FIRING, fields["status"]

    again = AlertProviders::Northflank.normalize(northflank_payload, source: @source).first[:fields]
    assert_equal fields["fingerprint"], again["fingerprint"]

    other_event = AlertProviders::Northflank.normalize(northflank_payload(event: "build:failure"), source: @source).first[:fields]
    assert_not_equal fields["fingerprint"], other_event["fingerprint"]
  end

  test "returns empty for payloads without an event" do
    assert_empty AlertProviders::Northflank.normalize({ "data" => {} }, source: @source)
    assert_empty AlertProviders::Northflank.normalize([ 1, 2 ], source: @source)
  end
end
