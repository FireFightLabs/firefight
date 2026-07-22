require "test_helper"

class RunbookAttachmentServiceTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_types,
           :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @runbook = @workspace.runbooks.create!(
      name: "Database outage response",
      summary: "Steps to triage a database outage",
      external_url: "https://runbooks.example.com/db"
    )
    @runbook.runbook_steps.create!(
      title: "Check connection pool",
      instruction: "Inspect current connection count against max_connections",
      position: 1
    )
    @runbook.runbook_steps.create!(title: "Failover to replica", position: 2)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT",
      source: Incident::SOURCE_SLACK
    )

    @service = RunbookAttachmentService.new(@workspace)
  end

  test "auto_attach attaches matching runbook and posts message" do
    @runbook.incident_conditions.create!(
      workspace: @workspace,
      condition_field: IncidentCondition::FIELD_SEVERITY,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ @severity.id ]
    )
    non_matching = @workspace.runbooks.create!(name: "Only for majors")
    non_matching.incident_conditions.create!(
      workspace: @workspace,
      condition_field: IncidentCondition::FIELD_SEVERITY,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ incident_severities(:major_ws1).id ]
    )
    stub_post_message

    @service.auto_attach(@incident)

    attached_runbooks = @incident.incident_runbooks.map(&:runbook)
    assert_includes attached_runbooks, @runbook
    assert_not_includes attached_runbooks, non_matching

    incident_runbook = @incident.incident_runbooks.find_by!(runbook: @runbook)
    assert_equal "1234567890.123456", incident_runbook.message_ts
    assert @incident.incident_events.exists?(event_type: IncidentEvent::RUNBOOK_ATTACHED)
  end

  test "attach is idempotent" do
    stub_post_message

    first = @service.attach(incident: @incident, runbook: @runbook, attached_by: @member)
    second = @service.attach(incident: @incident, runbook: @runbook, attached_by: @member)

    assert_equal first.id, second.id
    assert_equal 1, @incident.incident_runbooks.where(runbook: @runbook).count
  end

  test "apply creates one action per step in order and marks applied" do
    stub_post_message
    incident_runbook = @service.attach(incident: @incident, runbook: @runbook)
    stub_update_message

    assert_difference "@incident.incident_actions.count", 2 do
      @service.apply(incident_runbook: incident_runbook, applied_by: @member)
    end

    descriptions = @incident.incident_actions.order(:created_at).pluck(:description)
    assert_equal "Check connection pool\nInspect current connection count against max_connections", descriptions.first
    assert_equal "Failover to replica", descriptions.last

    incident_runbook.reload
    assert incident_runbook.applied?
    assert_equal @member, incident_runbook.applied_by
    assert @incident.incident_events.exists?(event_type: IncidentEvent::RUNBOOK_APPLIED)
  end

  test "apply is a no-op when already applied" do
    stub_post_message
    incident_runbook = @service.attach(incident: @incident, runbook: @runbook)
    stub_update_message
    @service.apply(incident_runbook: incident_runbook, applied_by: @member)

    assert_no_difference "@incident.incident_actions.count" do
      @service.apply(incident_runbook: incident_runbook, applied_by: @member)
    end
  end
end
