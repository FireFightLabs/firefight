require "test_helper"

class Slack::PrivateMetadataTest < ActiveSupport::TestCase
  test "encode emits a JSON object with only incident_id when other fields are absent" do
    encoded = Slack::PrivateMetadata.encode(incident_id: 42)

    assert_equal({ "incident_id" => 42 }, JSON.parse(encoded))
  end

  test "encode includes temp_message_ts and channel_id when provided" do
    encoded = Slack::PrivateMetadata.encode(
      incident_id: 42,
      temp_message_ts: "1700000000.000100",
      channel_id: "C12345"
    )

    assert_equal(
      { "incident_id" => 42, "temp_message_ts" => "1700000000.000100", "channel_id" => "C12345" },
      JSON.parse(encoded)
    )
  end

  test "encode omits nil temp_message_ts and channel_id rather than serializing nulls" do
    encoded = Slack::PrivateMetadata.encode(incident_id: 42, temp_message_ts: nil, channel_id: nil)

    refute_includes encoded, "temp_message_ts"
    refute_includes encoded, "channel_id"
  end

  test "parse returns a Result with all fields populated" do
    raw = Slack::PrivateMetadata.encode(
      incident_id: 42,
      temp_message_ts: "1700000000.000100",
      channel_id: "C12345"
    )

    result = Slack::PrivateMetadata.parse(raw)

    assert_equal 42, result.incident_id
    assert_equal "1700000000.000100", result.temp_message_ts
    assert_equal "C12345", result.channel_id
  end

  test "parse leaves optional fields nil when not encoded" do
    raw = Slack::PrivateMetadata.encode(incident_id: 42)

    result = Slack::PrivateMetadata.parse(raw)

    assert_equal 42, result.incident_id
    assert_nil result.temp_message_ts
    assert_nil result.channel_id
  end

  test "parse raises InvalidError when raw is nil" do
    assert_raises(Slack::PrivateMetadata::InvalidError) { Slack::PrivateMetadata.parse(nil) }
  end

  test "parse raises InvalidError when raw is an empty string" do
    assert_raises(Slack::PrivateMetadata::InvalidError) { Slack::PrivateMetadata.parse("") }
  end

  test "parse raises InvalidError when raw is not valid JSON" do
    error = assert_raises(Slack::PrivateMetadata::InvalidError) { Slack::PrivateMetadata.parse("not-json") }

    assert_match(/not valid JSON/, error.message)
  end

  test "parse raises InvalidError when JSON decodes to a non-object" do
    error = assert_raises(Slack::PrivateMetadata::InvalidError) { Slack::PrivateMetadata.parse("123") }

    assert_match(/must be a JSON object/, error.message)
  end

  test "parse raises InvalidError when JSON decodes to an array" do
    assert_raises(Slack::PrivateMetadata::InvalidError) { Slack::PrivateMetadata.parse("[1,2]") }
  end

  test "a modal that carries no incident parses with a nil incident_id" do
    result = Slack::PrivateMetadata.parse(%({"channel_id":"C1"}))

    assert_nil result.incident_id
    assert_equal "C1", result.channel_id
  end

  test "the source message a reaction carries survives the round trip" do
    encoded = Slack::PrivateMetadata.encode(incident_id: "inc-1", source_message_text: "db is down", source_message_link: "https://slack/p1")
    result = Slack::PrivateMetadata.parse(encoded)

    assert_equal "db is down", result.source_message_text
    assert_equal "https://slack/p1", result.source_message_link
    assert_nil result.temp_message_ts
  end
end
