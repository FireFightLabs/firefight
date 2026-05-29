require "test_helper"

class ProcessDomainEventJobTest < ActiveJob::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:critical_ws1),
      name: "Test incident",
      is_private: false,
      source: Incident::SOURCE_SLACK
    )
  end

  test "deserializes event hash and routes" do
    event_hash = {
      "event_type" => IncidentEvent::INCIDENT_CREATED,
      "incident_id" => @incident.id,
      "actor_type" => "WorkspaceMembership", "actor_id" => @member.id,
      "data" => { "severity" => "critical" },
      "occurred_at" => Time.current.iso8601(6)
    }

    EventRouter.expects(:route).with { |event|
      event.is_a?(DomainEvent) &&
        event.event_type == IncidentEvent::INCIDENT_CREATED &&
        event.incident_id == @incident.id
    }

    ProcessDomainEventJob.perform_now(event_hash)
  end

  test "discards on RecordNotFound" do
    event_hash = {
      "event_type" => IncidentEvent::INCIDENT_CREATED,
      "incident_id" => "nonexistent-id",
      "data" => {},
      "occurred_at" => Time.current.iso8601(6)
    }

    EventRouter.stubs(:route).raises(ActiveRecord::RecordNotFound)

    assert_nothing_raised do
      ProcessDomainEventJob.perform_now(event_hash)
    end
  end

  test "job is enqueued on events queue" do
    assert_equal "events", ProcessDomainEventJob.new.queue_name
  end
end
