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
end
