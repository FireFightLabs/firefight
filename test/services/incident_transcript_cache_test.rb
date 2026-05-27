require "test_helper"

class IncidentTranscriptCacheTest < ActiveSupport::TestCase
  fixtures :incidents, :workspaces, :users, :workspace_memberships, :incident_statuses, :incident_severities, :incident_lifecycle_stages

  setup do
    @incident = incidents(:active_critical_ws1)
    @cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(@cache)
  end

  test "appends entries and orders by ts" do
    IncidentTranscriptCache.append(incident: @incident, entry: { "ts" => "2.0", "text" => "second" })
    IncidentTranscriptCache.append(incident: @incident, entry: { "ts" => "1.0", "text" => "first" })

    entries = IncidentTranscriptCache.entries(@incident)

    assert_equal [ "first", "second" ], entries.map { |item| item["text"] }
  end

  test "caps transcript to max entries" do
    (IncidentTranscriptCache::MAX_ENTRIES + 5).times do |index|
      IncidentTranscriptCache.append(incident: @incident, entry: { "ts" => index.to_s, "text" => "m#{index}" })
    end

    entries = IncidentTranscriptCache.entries(@incident)

    assert_equal IncidentTranscriptCache::MAX_ENTRIES, entries.size
    assert_equal "m5", entries.first["text"]
  end

  test "can clear transcript" do
    IncidentTranscriptCache.append(incident: @incident, entry: { "ts" => "1.0", "text" => "one" })

    IncidentTranscriptCache.clear!(@incident)

    assert_empty IncidentTranscriptCache.entries(@incident)
  end

  test "append writes with ACTIVE_TTL so stale-open incidents fall out naturally" do
    Rails.cache.expects(:write).with(
      includes(":transcript"),
      anything,
      expires_in: IncidentTranscriptCache::ACTIVE_TTL
    )

    IncidentTranscriptCache.append(incident: @incident, entry: { "ts" => "1.0", "text" => "hi" })
  end

  test "expire_after_close uses CLOSED_TTL" do
    IncidentTranscriptCache.append(incident: @incident, entry: { "ts" => "1.0", "text" => "hi" })

    Rails.cache.expects(:write).with(
      includes(":transcript"),
      anything,
      expires_in: IncidentTranscriptCache::CLOSED_TTL
    )

    IncidentTranscriptCache.expire_after_close!(@incident)
  end

  test "clear_expiry resets to ACTIVE_TTL on reopen" do
    IncidentTranscriptCache.append(incident: @incident, entry: { "ts" => "1.0", "text" => "hi" })

    Rails.cache.expects(:write).with(
      includes(":transcript"),
      anything,
      expires_in: IncidentTranscriptCache::ACTIVE_TTL
    )

    IncidentTranscriptCache.clear_expiry!(@incident)
  end

  test "CLOSED_TTL covers the typical reopen window" do
    assert_operator IncidentTranscriptCache::CLOSED_TTL, :>=, 14.days,
      "CLOSED_TTL should cover at least a 2-week reopen window"
  end
end
