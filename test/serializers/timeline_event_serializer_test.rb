require "test_helper"

class TimelineEventSerializerTest < ActiveSupport::TestCase
  test "changes render aliased association names not raw field names" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)
    initial_status = incident.incident_status
    new_status = incident_statuses(:resolved_ws1)

    incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: member) { }

    incident.record_change!(IncidentEvent::INCIDENT_RESOLVED, by: member) do
      incident.update!(incident_status: new_status, resolved_at: Time.current)
    end

    event = incident.timeline_events.find { |e| e.event_type == IncidentEvent::INCIDENT_RESOLVED }
    rendered = TimelineEventSerializer.one(event)

    status_change = rendered[:changes].find { |c| c[:field] == "status" }
    assert_not_nil status_change, "expected status to appear in changes"
    assert_equal initial_status.name, status_change[:before]
    assert_equal new_status.name, status_change[:after]
  end

  test "the timeline links each update to the one before it from one load, not a query per row" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)
    severities = incident.workspace.incident_severities.active.ordered.to_a
    5.times do |i|
      incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: member) do
        incident.update!(incident_severity: severities[i % severities.size], summary: "update #{i}")
      end
    end

    events = incident.timeline_events
    queries = 0
    counter = ->(*) { queries += 1 }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      TimelineEventSerializer.many(events).to_json
    end

    updates = events.map(&:eventable).grep(IncidentUpdate)
    assert_equal updates[-2], updates[-1].previous_update
    assert_operator queries, :<=, 2, "serializing a loaded timeline ran #{queries} queries"
  end

  test "an automated event is attributed to Firefight" do
    incident = incidents(:active_critical_ws1)
    runbook = incident.workspace.runbooks.create!(name: "Failover")
    incident.incident_events.create!(
      event_type: IncidentEvent::RUNBOOK_ATTACHED,
      metadata: { runbook_id: runbook.id, runbook_slug: runbook.slug, runbook_name: runbook.name, reason: "Attached to every incident." }
    )

    rendered = TimelineEventSerializer.one(timeline_event(incident, IncidentEvent::RUNBOOK_ATTACHED))

    assert_equal "Firefight", rendered[:actor]
    assert rendered[:automated]
    assert_equal "attached the runbook", rendered[:description]
    assert_equal({ label: "Failover", href: "/app/settings/runbooks?runbook=#{runbook.id}" }, rendered[:subject])
    assert_equal "Attached to every incident.", rendered[:details]
  end

  test "a related incident is a link to that incident" do
    incident = incidents(:active_critical_ws1)
    other = incident.workspace.incidents.where.not(id: incident.id).first!
    incident.incident_events.create!(
      event_type: IncidentEvent::RELATIONSHIP_CREATED,
      actor: workspace_memberships(:alice_workspace_one),
      metadata: { related_incident_id: other.id, related_identifier: other.identifier }
    )

    rendered = TimelineEventSerializer.one(timeline_event(incident, IncidentEvent::RELATIONSHIP_CREATED))

    assert_equal({ label: other.identifier, href: "/app/incidents/#{other.id}" }, rendered[:subject])
    assert_not rendered[:automated]
  end

  test "an escalation names the person with their avatar and the reason" do
    incident = incidents(:active_critical_ws1)
    target = workspace_memberships(:bob_workspace_one)
    incident.incident_events.create!(
      event_type: IncidentEvent::INCIDENT_ESCALATED,
      actor: workspace_memberships(:alice_workspace_one),
      metadata: {
        escalated_to_platform_user_id: target.platform_user_id,
        escalated_to_member_id: target.id,
        escalated_to_name: target.display_name,
        reason: "Need a database owner"
      }
    )

    rendered = TimelineEventSerializer.one(timeline_event(incident, IncidentEvent::INCIDENT_ESCALATED))

    assert_equal "escalated the incident to", rendered[:description]
    assert_equal target.display_name, rendered[:person][:name]
    assert_nil rendered[:subject]
    assert_equal "Need a database owner", rendered[:details]
  end

  test "an action event carries the action's description, status and assignee" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)
    stub_post_message
    action = IncidentActionService.new(incident.workspace).create_action(
      incident: incident, created_by: member, action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Restart the worker pool", assignee: member
    )

    rendered = TimelineEventSerializer.one(timeline_event(incident, IncidentEvent::ACTION_CREATED))

    assert_equal "Restart the worker pool", rendered[:action][:description]
    assert_equal action.status, rendered[:action][:status]
    assert_equal member.display_name, rendered[:action][:assignee][:name]
  end

  test "a pin quotes the message and links to it" do
    incident = incidents(:active_critical_ws1)
    incident.incident_events.create!(
      event_type: IncidentEvent::MESSAGE_PINNED,
      metadata: { message_text: "Root cause found", permalink: "https://slack.example/p1" }
    )

    rendered = TimelineEventSerializer.one(timeline_event(incident, IncidentEvent::MESSAGE_PINNED))

    assert_equal({ text: "Root cause found", permalink: "https://slack.example/p1" }, rendered[:pin])
  end

  test "details surfaces the update message stored on the eventable" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)
    message = "Confirmed ~32% checkout error rate across all regions"

    incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: member, message: message)

    update = IncidentUpdate.find_by!(message: message)
    event = update.incident_event
    rendered = TimelineEventSerializer.one(event)

    assert_equal message, rendered[:details]
  end

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

  test "the attached blob supplies name, type and size when metadata predates them" do
    event = incident_events(:inc1_created)
    event.update!(event_type: IncidentEvent::MESSAGE_FILE_SHARED, metadata: { details: "shared a file" })
    event.artifact.attach(
      io: StringIO.new("png bytes here"),
      filename: "chart.png",
      content_type: "image/png"
    )

    rendered = TimelineEventSerializer.one(event)

    assert_equal "chart.png", rendered[:file][:name]
    assert_equal "image/png", rendered[:file][:mimeType]
    assert_equal "png bytes here".bytesize, rendered[:file][:byteSize]
  end

  test "the blob wins over stale metadata describing a different file" do
    event = incident_events(:inc1_created)
    event.update!(
      event_type: IncidentEvent::MESSAGE_FILE_SHARED,
      metadata: { file_name: "stale.txt", mime_type: "text/plain", byte_size: 1 }
    )
    event.artifact.attach(
      io: StringIO.new("png bytes here"),
      filename: "chart.png",
      content_type: "image/png"
    )

    rendered = TimelineEventSerializer.one(event)

    assert_equal "chart.png", rendered[:file][:name]
    assert_equal "image/png", rendered[:file][:mimeType]
    assert_equal "png bytes here".bytesize, rendered[:file][:byteSize]
  end

  test "metadata still describes the file when nothing was stored" do
    event = incident_events(:inc1_created)
    event.update!(
      event_type: IncidentEvent::MESSAGE_FILE_SHARED,
      metadata: { file_name: "notes.txt", mime_type: "text/plain", byte_size: 12, permalink: "https://slack.example/f/1" }
    )

    rendered = TimelineEventSerializer.one(event)

    assert_equal "notes.txt", rendered[:file][:name]
    assert_equal "text/plain", rendered[:file][:mimeType]
    assert_equal 12, rendered[:file][:byteSize]
    assert_nil rendered[:file][:downloadUrl]
  end

  test "no card renders when there is nothing to describe the file" do
    event = incident_events(:inc1_created)
    event.update!(event_type: IncidentEvent::MESSAGE_FILE_SHARED, metadata: { details: "shared a file" })

    assert_nil TimelineEventSerializer.one(event)[:file]
  end

  private

  def timeline_event(incident, event_type)
    incident.timeline_events.find { |event| event.event_type == event_type }
  end
end
