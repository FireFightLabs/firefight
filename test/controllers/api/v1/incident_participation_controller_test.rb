require "test_helper"

class Api::V1::IncidentParticipationControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @other = workspace_memberships(:bob_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @key = api_keys(:full_access_key)

    stub_post_message
    stub_update_message
    stub_post_ephemeral
    stub_invite_to_channel
  end

  test "escalating names a person and schedules the chase" do
    assert_enqueued_with(job: EscalationAcknowledgementReminderJob) do
      post escalate_api_v1_incident_url(@incident),
           params: { member_id: @other.user.email, reason: "Needs a database owner" },
           headers: api_headers, as: :json
    end

    assert_response :created
    assert_equal @other.actor_display_name, json_response.dig("escalated_to", "name")
    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_ESCALATED)
    assert_equal @key, event.actor
    assert_equal @other.id, event.metadata["escalated_to_member_id"]
  end

  test "an incident that is over cannot be escalated" do
    IncidentLifecycleService.new(@workspace).change_status(
      @incident, { incident_status: @workspace.incident_statuses.closed.active.first }, changed_by: @member
    )

    post escalate_api_v1_incident_url(@incident),
         params: { member_id: @other.user.email, reason: "Too late" },
         headers: api_headers, as: :json

    assert_response :unprocessable_entity
    assert_equal "incident_not_active", json_response.dig("error", "type")
  end

  test "inviting brings people into the channel and names them back" do
    post invite_api_v1_incident_url(@incident),
         params: { member_ids: [ @other.user.email ] }, headers: api_headers, as: :json

    assert_response :success
    assert_equal [ @other.actor_display_name ], json_response["invited"].map { |person| person["name"] }
  end

  test "linking two incidents records it on both timelines" do
    other = incidents(:active_major_ws1)

    post link_api_v1_incident_url(@incident),
         params: { other_incident_id: other.id, relationship: IncidentRelationship::RELATED },
         headers: api_headers, as: :json

    assert_response :created
    assert @incident.incident_events.exists?(event_type: IncidentEvent::RELATIONSHIP_CREATED)
    assert other.incident_events.exists?(event_type: IncidentEvent::RELATIONSHIP_CREATED)
  end

  test "marking a duplicate cancels this incident into the other" do
    other = incidents(:active_major_ws1)

    post link_api_v1_incident_url(@incident),
         params: { other_incident_id: other.id, relationship: IncidentRelationship::DUPLICATE },
         headers: api_headers, as: :json

    assert_response :created
    assert @incident.reload.canceled?
  end

  # The service refuses, so a surface that never thought to ask still cannot
  # post into a channel that is gone.
  test "an incident that is over refuses an invite and a shoutout" do
    close_incident

    post invite_api_v1_incident_url(@incident),
         params: { member_ids: [ @other.user.email ] }, headers: api_headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "incident_not_active", json_response.dig("error", "type")

    post shoutout_api_v1_incident_url(@incident),
         params: { member_id: @other.user.email, message: "Nice work" }, headers: api_headers, as: :json
    assert_response :unprocessable_entity
    assert_empty @incident.shoutouts
  end

  test "an incident cannot be linked to itself" do
    post link_api_v1_incident_url(@incident),
         params: { other_incident_id: @incident.id, relationship: IncidentRelationship::RELATED },
         headers: api_headers, as: :json

    assert_response :unprocessable_entity
  end

  test "a shoutout records who gave it and who got it" do
    post shoutout_api_v1_incident_url(@incident),
         params: { member_id: @other.user.email, message: "Found the leak in minutes" },
         headers: api_headers, as: :json

    assert_response :created
    shoutout = @incident.shoutouts.find_by!(to_member_id: @other.id)
    assert_equal @key, shoutout.from_member
  end

  test "claiming a runbook step opens the item behind it" do
    attachment = attach_runbook
    step = attachment.runbook.runbook_steps.first

    post claim_runbook_step_api_v1_incident_url(@incident),
         params: { runbook_id: attachment.id, step_id: step.id },
         headers: api_headers, as: :json

    assert_response :created
    action = @incident.incident_actions.active.find_by!(runbook_step: step)
    assert_equal @key, action.assignee
    assert_equal step.title, json_response["description"]
  end

  test "a read-only key cannot escalate" do
    post escalate_api_v1_incident_url(@incident),
         params: { member_id: @other.user.email, reason: "Nope" },
         headers: api_headers(token: "ff_test_read_only_token_12345678"), as: :json

    assert_response :forbidden
    assert_not @incident.incident_events.exists?(event_type: IncidentEvent::INCIDENT_ESCALATED)
  end

  test "another workspace's incident is not reachable" do
    post invite_api_v1_incident_url(incidents(:active_p0_ws2)),
         params: { member_ids: [ @other.user.email ] }, headers: api_headers, as: :json

    assert_response :not_found
  end

  private

  def close_incident
    stub_set_channel_topic
    IncidentLifecycleService.new(@workspace).change_status(
      @incident, { incident_status: @workspace.incident_statuses.closed.active.first }, changed_by: @member
    )
  end

  def attach_runbook
    runbook = @workspace.runbooks.create!(name: "Database failover", slug: "database_failover")
    runbook.runbook_steps.create!(title: "Drain the primary", position: 1)

    RunbookAttachmentService.new(@workspace).attach_by_slug(
      incident: @incident, slug: runbook.slug, attached_by: @member
    )
  end
end
