require "test_helper"

class IncidentLifecycleServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incident_types, :incident_roles,
           :incidents, :incident_events

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    @service = IncidentLifecycleService.new(@workspace)
    stub_successful_slack_workflow
  end

  # ============================================================================
  # CREATE
  # ============================================================================

  test "create creates incident and starts workflow" do
    severity = @workspace.incident_severities.active.first
    status = @workspace.incident_statuses.default_status

    incident = nil
    assert_difference -> { Incident.count }, 1 do
      incident = @service.create(
        declared_by: @member,
        incident_status: status,
        incident_severity: severity,
        name: "Service create test",
        source: Incident::SOURCE_SLACK
      )
    end

    assert incident.persisted?
    assert_equal "Service create test", incident.name
    assert_equal @workspace, incident.workspace
    assert_not_nil incident.identifier
  end

  test "create starts IncidentCreationWorkflow" do
    severity = @workspace.incident_severities.active.first
    status = @workspace.incident_statuses.default_status

    assert_enqueued_with(job: SolidWorkflow::RunStepJob) do
      @service.create(
        declared_by: @member,
        incident_status: status,
        incident_severity: severity,
        name: "Workflow test",
        source: Incident::SOURCE_SLACK
      )
    end
  end

  test "create with create_channel_sync: true creates channel synchronously" do
    severity = @workspace.incident_severities.active.first
    status = @workspace.incident_statuses.default_status

    incident = @service.create(
      declared_by: @member,
      incident_status: status,
      incident_severity: severity,
      name: "Slack sync channel test",
      source: Incident::SOURCE_SLACK,
      create_channel_sync: true
    )

    assert_equal "C12345678", incident.channel_id
    assert_equal "incidents", incident.channel_name
  end

  test "create without create_channel_sync does not create channel synchronously" do
    severity = @workspace.incident_severities.active.first
    status = @workspace.incident_statuses.default_status

    incident = @service.create(
      declared_by: @member,
      incident_status: status,
      incident_severity: severity,
      name: "API creation test",
      source: "datadog"
    )

    assert_nil incident.channel_id
  end

  # ============================================================================
  # UPDATE
  # ============================================================================

  test "update records change with INCIDENT_UPDATED event" do
    assert_difference -> { @incident.incident_events.count }, 1 do
      @service.update(@incident, { summary: "Updated via service" }, changed_by: @member)
    end

    assert_equal "Updated via service", @incident.reload.summary
    assert @incident.incident_events.exists?(event_type: IncidentEvent::INCIDENT_UPDATED)
  end

  test "update starts IncidentUpdateWorkflow with previous state context" do
    assert_enqueued_with(job: SolidWorkflow::RunStepJob) do
      @service.update(
        @incident,
        { incident_severity: @workspace.incident_severities.active.last },
        changed_by: @member
      )
    end
  end

  test "update passes message to record_change" do
    @service.update(@incident, { summary: "Changed" }, changed_by: @member, message: "Status update")

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_UPDATED)
    update = IncidentUpdate.find_by!(incident: @incident, update_type: IncidentUpdate::UPDATED)
    assert_equal "Status update", update.message
  end

  # ============================================================================
  # CLOSE
  # ============================================================================

  test "close records change with INCIDENT_RESOLVED event" do
    resolved_status = @workspace.incident_statuses.closed.first

    assert_difference -> { @incident.incident_events.count }, 1 do
      @service.close(@incident, { incident_status: resolved_status }, changed_by: @member)
    end

    assert @incident.incident_events.exists?(event_type: IncidentEvent::INCIDENT_RESOLVED)
    assert_equal resolved_status, @incident.reload.incident_status
  end

  test "close expires transcript cache" do
    resolved_status = @workspace.incident_statuses.closed.first
    IncidentTranscriptCache.expects(:expire_after_close!).with(@incident)

    @service.close(@incident, { incident_status: resolved_status }, changed_by: @member)
  end

  test "close starts IncidentCloseWorkflow" do
    resolved_status = @workspace.incident_statuses.closed.first

    assert_enqueued_with(job: SolidWorkflow::RunStepJob) do
      @service.close(@incident, { incident_status: resolved_status }, changed_by: @member)
    end
  end

  test "close schedules channel archival when enabled" do
    resolved_status = @workspace.incident_statuses.closed.first
    @workspace.update!(archive_channel_enabled: true, archive_channel_delay_minutes: 30)

    assert_enqueued_with(job: ChannelArchivalJob) do
      @service.close(@incident, { incident_status: resolved_status }, changed_by: @member)
    end
  end

  test "close sets lead if provided in attrs" do
    resolved_status = @workspace.incident_statuses.closed.first
    lead = workspace_memberships(:bob_workspace_one)

    @service.close(@incident, { incident_status: resolved_status, lead: lead }, changed_by: @member)

    assert_equal lead, @incident.reload.lead
  end

  # ============================================================================
  # REOPEN
  # ============================================================================

  test "reopen records change with INCIDENT_REOPENED event" do
    close_incident!

    default_status = @workspace.incident_statuses.live.find_by(is_default: true)

    assert_difference -> { @incident.incident_events.count }, 1 do
      @service.reopen(@incident, { incident_status: default_status }, changed_by: @member)
    end

    assert @incident.incident_events.exists?(event_type: IncidentEvent::INCIDENT_REOPENED)
  end

  test "reopen clears transcript cache expiry" do
    close_incident!

    default_status = @workspace.incident_statuses.live.find_by(is_default: true)
    IncidentTranscriptCache.expects(:clear_expiry!).with(@incident)

    @service.reopen(@incident, { incident_status: default_status }, changed_by: @member)
  end

  test "reopen stores reason in event details" do
    close_incident!

    default_status = @workspace.incident_statuses.live.find_by(is_default: true)
    @service.reopen(@incident, { incident_status: default_status }, changed_by: @member, reason: "False alarm resolved")

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_REOPENED)
    assert_equal "False alarm resolved", event.eventable.message
  end

  test "reopen starts IncidentReopenWorkflow" do
    close_incident!

    default_status = @workspace.incident_statuses.live.find_by(is_default: true)

    assert_enqueued_with(job: SolidWorkflow::RunStepJob) do
      @service.reopen(@incident, { incident_status: default_status }, changed_by: @member)
    end
  end

  # ============================================================================
  # ASSIGN LEAD
  # ============================================================================

  test "assign_lead records change with LEAD_ASSIGNED event" do
    lead = workspace_memberships(:bob_workspace_one)

    assert_difference -> { @incident.incident_events.count }, 1 do
      @service.assign_lead(@incident, lead, changed_by: @member)
    end

    assert @incident.incident_events.exists?(event_type: IncidentEvent::LEAD_ASSIGNED)
    assert_equal lead, @incident.reload.lead
  end

  test "assign_lead starts LeadAssignmentWorkflow with lead platform_user_id" do
    lead = workspace_memberships(:bob_workspace_one)

    assert_enqueued_with(job: SolidWorkflow::RunStepJob) do
      @service.assign_lead(@incident, lead, changed_by: @member)
    end
  end

  # ============================================================================
  # WORKFLOW CONTEXT
  # ============================================================================

  test "update passes changed_by platform_user_id in workflow context" do
    SolidWorkflow::Base.any_instance.stubs(:enqueue_ready_steps)
    @service.update(@incident, { summary: "Test" }, changed_by: @member)

    workflow = SolidWorkflow::Workflow.last
    assert_equal @member.platform_user_id, workflow.context["updated_by_platform_user_id"]
  end

  test "close passes changed_by platform_user_id in workflow context" do
    resolved_status = @workspace.incident_statuses.closed.first
    SolidWorkflow::Base.any_instance.stubs(:enqueue_ready_steps)

    @service.close(@incident, { incident_status: resolved_status }, changed_by: @member)

    workflow = SolidWorkflow::Workflow.last
    assert_equal @member.platform_user_id, workflow.context["resolved_by_platform_user_id"]
  end

  test "assign_lead passes lead platform_user_id in workflow context" do
    lead = workspace_memberships(:bob_workspace_one)
    SolidWorkflow::Base.any_instance.stubs(:enqueue_ready_steps)

    @service.assign_lead(@incident, lead, changed_by: @member)

    workflow = SolidWorkflow::Workflow.last
    assert_equal lead.platform_user_id, workflow.context["lead_platform_user_id"]
  end

  private

  def close_incident!
    resolved_status = @workspace.incident_statuses.closed.first
    @incident.update!(incident_status: resolved_status, resolved_at: Time.current)
  end
end
