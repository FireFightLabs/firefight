require "test_helper"

class TimelineEventSerializerTest < ActiveSupport::TestCase
  fixtures :incident_events, :incidents, :workspaces, :incident_statuses,
           :incident_severities, :incident_lifecycle_stages,
           :workspace_memberships, :users

  test "file field is nil for non-file events" do
    event = incident_events(:inc1_created)
    rendered = TimelineEventSerializer.one(event)
    assert_nil rendered[:file]
  end

  test "file field exposes metadata for file-shared events" do
    event = incident_events(:inc1_created)
    event.update!(
      event_type: IncidentEvent::MESSAGE_FILE_SHARED,
      metadata: {
        file_name: "runbook.png",
        mime_type: "image/png",
        permalink: "https://example.slack.com/archives/C1/p123",
        byte_size: 2048
      }
    )

    rendered = TimelineEventSerializer.one(event)

    assert_equal "runbook.png", rendered[:file][:name]
    assert_equal "image/png", rendered[:file][:mimeType]
    assert_equal "https://example.slack.com/archives/C1/p123", rendered[:file][:slackPermalink]
    assert_equal 2048, rendered[:file][:byteSize]
    assert_nil rendered[:file][:downloadUrl]
  end

  test "downloadUrl is present once artifact is attached" do
    event = incident_events(:inc1_created)
    event.update!(event_type: IncidentEvent::MESSAGE_FILE_SHARED, metadata: { file_name: "doc.pdf" })
    event.artifact.attach(
      io: StringIO.new("pdf bytes"),
      filename: "doc.pdf",
      content_type: "application/pdf"
    )

    rendered = TimelineEventSerializer.one(event)

    assert_not_nil rendered[:file][:downloadUrl]
    assert_match(%r{/rails/active_storage/}, rendered[:file][:downloadUrl])
  end

  test "blank permalink and mime_type serialize as nil" do
    event = incident_events(:inc1_created)
    event.update!(
      event_type: IncidentEvent::MESSAGE_FILE_SHARED,
      metadata: { file_name: "thing.bin", permalink: "", mime_type: "" }
    )

    rendered = TimelineEventSerializer.one(event)

    assert_nil rendered[:file][:slackPermalink]
    assert_nil rendered[:file][:mimeType]
  end
end
