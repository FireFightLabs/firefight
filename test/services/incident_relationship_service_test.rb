require "test_helper"

class IncidentRelationshipServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper


  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @service = IncidentRelationshipService.new(@workspace)
    @incident1 = incidents(:active_critical_ws1)
    @incident2 = incidents(:active_major_ws1)
  end

  # Link related

  test "link_related creates relationship" do
    assert_difference "IncidentRelationship.count", 1 do
      @service.link_related(source: @incident1, target: @incident2, created_by: @member)
    end

    rel = IncidentRelationship.find_by!(
      incident: @incident1,
      related_incident: @incident2,
      relationship_type: IncidentRelationship::RELATED
    )
    assert_equal IncidentRelationship::RELATED, rel.relationship_type
    assert_equal @incident1, rel.incident
    assert_equal @incident2, rel.related_incident
  end

  test "link_related creates events on both incidents" do
    assert_difference "IncidentEvent.count", 2 do
      @service.link_related(source: @incident1, target: @incident2, created_by: @member)
    end

    event1 = @incident1.incident_events.find_by!(event_type: IncidentEvent::RELATIONSHIP_CREATED)
    assert_equal @member, event1.actor
    assert_equal @incident2.id, event1.metadata["related_incident_id"]

    event2 = @incident2.incident_events.find_by!(event_type: IncidentEvent::RELATIONSHIP_CREATED)
    assert_equal @incident1.id, event2.metadata["related_incident_id"]
  end

  test "link_related is idempotent" do
    @service.link_related(source: @incident1, target: @incident2, created_by: @member)

    assert_no_difference "IncidentRelationship.count" do
      @service.link_related(source: @incident1, target: @incident2, created_by: @member)
    end
  end

  test "link_related is idempotent in reverse direction" do
    @service.link_related(source: @incident1, target: @incident2, created_by: @member)

    assert_no_difference "IncidentRelationship.count" do
      @service.link_related(source: @incident2, target: @incident1, created_by: @member)
    end
  end

  # Mark duplicate

  test "mark_duplicate creates relationship" do
    assert_difference "IncidentRelationship.count", 1 do
      @service.mark_duplicate(source: @incident1, canonical: @incident2, created_by: @member)
    end

    rel = IncidentRelationship.find_by!(
      incident: @incident1,
      related_incident: @incident2,
      relationship_type: IncidentRelationship::DUPLICATE
    )
    assert_equal IncidentRelationship::DUPLICATE, rel.relationship_type
    assert_equal @incident1, rel.incident
    assert_equal @incident2, rel.related_incident
  end

  test "mark_duplicate cancels the source incident" do
    @service.mark_duplicate(source: @incident1, canonical: @incident2, created_by: @member)

    @incident1.reload
    assert @incident1.canceled?
  end

  test "mark_duplicate creates MERGED_INTO event on source" do
    @service.mark_duplicate(source: @incident1, canonical: @incident2, created_by: @member)

    event = @incident1.incident_events.find_by!(event_type: IncidentEvent::MERGED_INTO)
    assert_equal @member, event.actor
  end

  test "mark_duplicate creates MARKED_DUPLICATE event on canonical" do
    @service.mark_duplicate(source: @incident1, canonical: @incident2, created_by: @member)

    event = @incident2.incident_events.find_by!(event_type: IncidentEvent::MARKED_DUPLICATE)
    assert_equal @incident1.id, event.metadata["related_incident_id"]
  end

  test "mark_duplicate creates incident update snapshot" do
    assert_difference "IncidentUpdate.count", 1 do
      @service.mark_duplicate(source: @incident1, canonical: @incident2, created_by: @member)
    end
  end

  test "mark_duplicate schedules channel archival when enabled" do
    @workspace.update!(archive_channel_enabled: true, archive_channel_delay_minutes: 30)

    assert_enqueued_with(job: ChannelArchivalJob, args: [ @incident1.id ]) do
      @service.mark_duplicate(source: @incident1, canonical: @incident2, created_by: @member)
    end
  end

  test "mark_duplicate does not schedule channel archival when disabled" do
    @workspace.update!(archive_channel_enabled: false)

    @service.mark_duplicate(source: @incident1, canonical: @incident2, created_by: @member)

    assert_no_enqueued_jobs(only: ChannelArchivalJob)
  end

  test "mark_duplicate does not schedule channel archival without a channel" do
    @workspace.update!(archive_channel_enabled: true)
    @incident1.update!(channel_id: nil)

    @service.mark_duplicate(source: @incident1, canonical: @incident2, created_by: @member)

    assert_no_enqueued_jobs(only: ChannelArchivalJob)
  end
end
