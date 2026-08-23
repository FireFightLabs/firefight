require "test_helper"

class Api::V1::IncidentsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incident_types, :incidents,
           :api_keys, :ability_actions, :ability_grants, :idempotency_keys

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @severity = @workspace.incident_severities.active.first
    @status = @workspace.incident_statuses.default_status
  end

  # Authentication

  test "a member's personal token participates in incidents but cannot configure the workspace" do
    membership = workspace_memberships(:bob_workspace_one)
    _, raw = ApiKey.create_with_token!(
      workspace: @workspace, created_by: membership, on_behalf_of: membership, name: "Personal"
    )
    headers = { "Authorization" => "Bearer #{raw}" }

    get api_v1_incidents_url, headers: headers, as: :json
    assert_response :success

    post api_v1_incidents_url, headers: headers, params: {
      idempotency_key: SecureRandom.uuid, name: "Member declared", severity_id: @severity.id
    }, as: :json
    assert_response :created

    post api_v1_catalog_type_entries_url(slug: "service"), headers: headers,
         params: { name: "Nope" }, as: :json
    assert_response :forbidden
  end

  test "returns 401 without authorization" do
    get api_v1_incidents_url
    assert_response :unauthorized
  end

  test "returns 401 with expired token" do
    get api_v1_incidents_url, headers: api_headers(token: "ff_test_expired_token_1234567890")
    assert_response :unauthorized
  end

  test "returns 401 with inactive token" do
    get api_v1_incidents_url, headers: api_headers(token: "ff_test_inactive_token_123456789")
    assert_response :unauthorized
  end

  # Permissions

  test "returns 403 when key lacks create permission" do
    post api_v1_incidents_url,
      params: { idempotency_key: "test", name: "Test", severity_id: @severity.id }.to_json,
      headers: api_headers(token: "ff_test_read_only_token_12345678")
    assert_response :forbidden
  end

  # Index

  test "lists incidents for the workspace" do
    get api_v1_incidents_url, headers: api_headers
    assert_response :success

    data = json_response
    assert data.key?("incidents")
    assert data.key?("pagination")
    assert data["incidents"].is_a?(Array)
    assert data["pagination"]["total"].is_a?(Integer)
  end

  test "paginates incidents" do
    get api_v1_incidents_url, params: { page: 1, per_page: 2 }, headers: api_headers
    assert_response :success

    data = json_response
    assert data["incidents"].length <= 2
    assert_equal 1, data["pagination"]["page"]
    assert_equal 2, data["pagination"]["per_page"]
  end

  test "filters incidents by severity" do
    get api_v1_incidents_url, params: { severity_id: @severity.id }, headers: api_headers
    assert_response :success

    json_response["incidents"].each do |incident|
      assert_equal @severity.id, incident["severity"]["id"]
    end
  end

  test "does not return incidents from other workspaces" do
    get api_v1_incidents_url, headers: api_headers(token: "ff_test_ws2_token_1234567890abcd")
    assert_response :success

    ws2 = workspaces(:slack_workspace_two)
    json_response["incidents"].each do |incident|
      db_incident = Incident.find(incident["id"])
      assert_equal ws2.id, db_incident.workspace_id
    end
  end

  # Show

  test "shows incident details" do
    incident = incidents(:active_critical_ws1)
    get api_v1_incident_url(incident), headers: api_headers
    assert_response :success

    data = json_response["incident"]
    assert_equal incident.id, data["id"]
    assert_equal incident.identifier, data["identifier"]
    assert_equal incident.name, data["name"]
    assert data.key?("status")
    assert data.key?("severity")
    assert data.key?("declared_by")
    assert data.key?("declared_at")
    assert data.key?("custom_fields")
  end

  test "embeds the slug alongside every option a consumer might match on" do
    incident = incidents(:active_critical_ws1)
    get api_v1_incident_url(incident), headers: api_headers
    assert_response :success

    data = json_response["incident"]
    assert_equal incident.incident_status.slug, data["status"]["slug"]
    assert_equal incident.incident_severity.slug, data["severity"]["slug"]
  end

  test "returns 404 for incident from different workspace" do
    ws2_incident = incidents(:active_p0_ws2)
    get api_v1_incident_url(ws2_incident), headers: api_headers
    assert_response :not_found
  end

  # Create

  test "creates incident with required fields" do
    stub_successful_slack_workflow

    assert_difference -> { Incident.count }, 1 do
      post api_v1_incidents_url,
        params: {
          idempotency_key: "api-create-test-#{SecureRandom.hex(8)}",
          name: "API Created Incident",
          severity_id: @severity.id
        }.to_json,
        headers: api_headers
    end

    assert_response :created

    data = json_response["incident"]
    assert_equal "API Created Incident", data["name"]
    assert_not_nil data["identifier"]
    assert_not_nil data["declared_at"]
    assert_equal "public", data["visibility"]
  end

  test "creates incident with all optional fields" do
    stub_successful_slack_workflow

    incident_type = @workspace.incident_types.active.first
    skip "No incident types in fixtures" unless incident_type

    post api_v1_incidents_url,
      params: {
        idempotency_key: "api-create-full-#{SecureRandom.hex(8)}",
        name: "Full Incident",
        severity_id: @severity.id,
        summary: "Detailed description",
        visibility: "private",
        incident_type_id: incident_type.id
      }.to_json,
      headers: api_headers

    assert_response :created

    data = json_response["incident"]
    assert_equal "Full Incident", data["name"]
    assert_equal "Detailed description", data["summary"]
    assert_equal "private", data["visibility"]
  end

  test "returns 400 when idempotency_key is missing" do
    post api_v1_incidents_url,
      params: { name: "Test", severity_id: @severity.id }.to_json,
      headers: api_headers
    assert_response :bad_request
  end

  test "returns 400 when name is missing" do
    post api_v1_incidents_url,
      params: { idempotency_key: "test-key", severity_id: @severity.id }.to_json,
      headers: api_headers
    assert_response :bad_request
  end

  test "returns existing incident for duplicate idempotency_key" do
    stub_successful_slack_workflow

    key = "idempotent-test-#{SecureRandom.hex(8)}"

    post api_v1_incidents_url,
      params: { idempotency_key: key, name: "First", severity_id: @severity.id }.to_json,
      headers: api_headers
    assert_response :created
    first_id = json_response["incident"]["id"]

    assert_no_difference -> { Incident.count } do
      post api_v1_incidents_url,
        params: { idempotency_key: key, name: "Second", severity_id: @severity.id }.to_json,
        headers: api_headers
    end
    assert_response :ok
    assert_equal first_id, json_response["incident"]["id"]
  end

  test "a unique violation unrelated to the idempotency key is not reported as a replay" do
    stub_successful_slack_workflow
    Incident.any_instance.stubs(:save!).raises(ActiveRecord::RecordNotUnique, "identifier taken")

    assert_raises(ActiveRecord::RecordNotUnique) do
      post api_v1_incidents_url,
        params: { idempotency_key: "race-#{SecureRandom.hex(8)}", name: "Raced", severity_id: @severity.id }.to_json,
        headers: api_headers
    end
  end

  test "losing the idempotency key race replays the committed incident" do
    stub_successful_slack_workflow
    key = "race-#{SecureRandom.hex(8)}"
    winner = @workspace.incidents.create!(
      declared_by: workspace_memberships(:alice_workspace_one), incident_status: @status,
      incident_severity: @severity, name: "Winner", source: "api"
    )
    IdempotencyKey.create!(workspace: @workspace, key: key, resource_type: IdempotencyKey::RESOURCE_INCIDENT, resource_id: winner.id)
    Api::V1::IncidentsController.any_instance.stubs(:replayed?).returns(false)

    assert_no_difference -> { Incident.count } do
      post api_v1_incidents_url,
        params: { idempotency_key: key, name: "Loser", severity_id: @severity.id }.to_json,
        headers: api_headers
    end
    assert_response :ok
    assert_equal winner.id, json_response["incident"]["id"]
  end

  test "triggers incident creation workflow" do
    stub_successful_slack_workflow

    assert_enqueued_with(job: SolidWorkflow::RunStepJob) do
      post api_v1_incidents_url,
        params: {
          idempotency_key: "workflow-test-#{SecureRandom.hex(8)}",
          name: "Workflow Test",
          severity_id: @severity.id
        }.to_json,
        headers: api_headers
    end
  end

  # Update

  test "updates incident name and summary" do
    incident = incidents(:active_critical_ws1)

    patch api_v1_incident_url(incident),
      params: { name: "Updated Name", summary: "Updated summary" }.to_json,
      headers: api_headers

    assert_response :ok

    data = json_response["incident"]
    assert_equal "Updated Name", data["name"]
    assert_equal "Updated summary", data["summary"]
  end

  test "updates incident severity" do
    incident = incidents(:active_critical_ws1)
    new_severity = @workspace.incident_severities.active.where.not(id: incident.incident_severity_id).first

    patch api_v1_incident_url(incident),
      params: { severity_id: new_severity.id }.to_json,
      headers: api_headers

    assert_response :ok
    assert_equal new_severity.id, json_response["incident"]["severity"]["id"]
  end

  test "canceling over the API records a cancel and still archives the channel" do
    incident = incidents(:active_critical_ws1)
    canceled = @workspace.incident_statuses.canceled.active.first
    @workspace.update!(archive_channel_enabled: true, archive_channel_delay_minutes: 30)

    assert_enqueued_with(job: ChannelArchivalJob) do
      patch api_v1_incident_url(incident), params: { status_id: canceled.id }.to_json, headers: api_headers
    end

    assert_response :ok
    assert incident.incident_events.exists?(event_type: IncidentEvent::INCIDENT_CANCELED)
    assert_not incident.incident_events.exists?(event_type: IncidentEvent::INCIDENT_RESOLVED)
    assert_nil incident.reload.resolved_at
  end

  test "a closed incident cannot be canceled over the API without reopening" do
    incident = incidents(:active_critical_ws1)
    closed = @workspace.incident_statuses.closed.active.first
    canceled = @workspace.incident_statuses.canceled.active.first
    patch api_v1_incident_url(incident), params: { status_id: closed.id }.to_json, headers: api_headers
    assert_response :ok

    patch api_v1_incident_url(incident), params: { status_id: canceled.id }.to_json, headers: api_headers

    assert_response :unprocessable_entity
    assert_match(/reopened first/, json_response.dig("error", "message"))
    assert_equal closed.id, incident.reload.incident_status_id
  end

  test "every field in one PATCH lands, whatever the status change" do
    incident = incidents(:active_critical_ws1)
    closed = @workspace.incident_statuses.closed.active.first
    live = @workspace.incident_statuses.live.find_by(is_default: true)
    other_type = @workspace.incident_types.active.first
    lead = workspace_memberships(:bob_workspace_one)

    patch api_v1_incident_url(incident),
      params: { status_id: closed.id, incident_type_id: other_type.id, lead_id: lead.id, name: "Closed with type" }.to_json,
      headers: api_headers
    assert_response :ok
    incident.reload
    assert_equal closed.id, incident.incident_status_id
    assert_equal other_type.id, incident.incident_type_id
    assert_equal lead, incident.lead
    assert_equal "Closed with type", incident.name

    severity = @workspace.incident_severities.active.where.not(id: incident.incident_severity_id).first
    patch api_v1_incident_url(incident),
      params: { status_id: live.id, severity_id: severity.id, summary: "Back on" }.to_json,
      headers: api_headers
    assert_response :ok
    incident.reload
    assert_equal live.id, incident.incident_status_id
    assert_equal severity.id, incident.incident_severity_id
    assert_equal "Back on", incident.summary
    assert incident.incident_events.exists?(event_type: IncidentEvent::INCIDENT_REOPENED)
  end

  test "a lead with a name change lands both, and a lead alone keeps its own event" do
    incident = incidents(:active_critical_ws1)
    lead = workspace_memberships(:bob_workspace_one)

    patch api_v1_incident_url(incident), params: { lead_id: lead.id, name: "Renamed" }.to_json, headers: api_headers
    assert_response :ok
    assert_equal "Renamed", incident.reload.name
    assert_equal lead, incident.lead

    other = workspace_memberships(:alice_workspace_one)
    assert_difference -> { incident.incident_events.where(event_type: IncidentEvent::LEAD_ASSIGNED).count }, 1 do
      patch api_v1_incident_url(incident), params: { lead_id: other.id }.to_json, headers: api_headers
    end
    assert_equal other, incident.reload.lead
  end

  test "clearing the lead is refused with the reason instead of crashing" do
    incident = incidents(:active_critical_ws1)
    lead = workspace_memberships(:bob_workspace_one)
    patch api_v1_incident_url(incident), params: { lead_id: lead.id }.to_json, headers: api_headers

    patch api_v1_incident_url(incident), params: { lead_id: nil }.to_json, headers: api_headers

    assert_response :unprocessable_entity
    assert_match(/cannot be cleared/, json_response.dig("error", "message"))
    assert_equal lead, incident.reload.lead
  end

  test "update creates incident event" do
    incident = incidents(:active_critical_ws1)

    assert_difference -> { incident.incident_events.count }, 1 do
      patch api_v1_incident_url(incident),
        params: { summary: "Changed via API" }.to_json,
        headers: api_headers
    end
  end

  test "update triggers IncidentUpdateWorkflow" do
    incident = incidents(:active_critical_ws1)
    stub_successful_slack_workflow

    assert_enqueued_with(job: SolidWorkflow::RunStepJob) do
      patch api_v1_incident_url(incident),
        params: { summary: "Updated via API" }.to_json,
        headers: api_headers
    end
  end

  test "API-driven update attributes the event to the API key, not the key creator" do
    incident = incidents(:active_critical_ws1)
    stub_successful_slack_workflow

    patch api_v1_incident_url(incident),
      params: { summary: "Updated via API" }.to_json,
      headers: api_headers

    event = incident.incident_events.where(event_type: IncidentEvent::INCIDENT_UPDATED).order(:created_at).last
    assert_instance_of ApiKey, event.actor
    assert_equal "Full Access Key", event.actor.actor_display_name
  end

  test "closing via status triggers IncidentCloseWorkflow" do
    incident = incidents(:active_critical_ws1)
    resolved_status = @workspace.incident_statuses.closed.first
    stub_successful_slack_workflow

    assert_enqueued_with(job: SolidWorkflow::RunStepJob) do
      patch api_v1_incident_url(incident),
        params: { status_id: resolved_status.id }.to_json,
        headers: api_headers
    end

    assert incident.incident_events.exists?(event_type: IncidentEvent::INCIDENT_RESOLVED)
  end

  test "assigning lead triggers LeadAssignmentWorkflow" do
    incident = incidents(:active_critical_ws1)
    lead = workspace_memberships(:bob_workspace_one)
    stub_successful_slack_workflow

    assert_enqueued_with(job: SolidWorkflow::RunStepJob) do
      patch api_v1_incident_url(incident),
        params: { lead_id: lead.id }.to_json,
        headers: api_headers
    end

    assert incident.incident_events.exists?(event_type: IncidentEvent::LEAD_ASSIGNED)
  end

  test "refuses to assign a lead on a closed incident" do
    incident = incidents(:active_critical_ws1)
    incident.update!(incident_status: incident_statuses(:resolved_ws1))
    lead = workspace_memberships(:bob_workspace_one)

    assert_no_difference "IncidentEvent.count" do
      patch api_v1_incident_url(incident),
        params: { lead_id: lead.id }.to_json,
        headers: api_headers
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "incident_not_active", body.dig("error", "type")
    assert_equal "#{incident.identifier} is closed, so it can no longer be assigned a lead.",
                 body.dig("error", "message")
    assert_nil incident.reload.lead
  end

  test "refuses to assign a lead on a canceled incident" do
    incident = incidents(:active_critical_ws1)
    incident.update!(incident_status: incident_statuses(:canceled_ws1))

    patch api_v1_incident_url(incident),
      params: { lead_id: workspace_memberships(:bob_workspace_one).id }.to_json,
      headers: api_headers

    assert_response :unprocessable_entity
    assert_equal "#{incident.identifier} is canceled, so it can no longer be assigned a lead.",
                 JSON.parse(response.body).dig("error", "message")
  end

  test "returns 404 when updating incident from different workspace" do
    ws2_incident = incidents(:active_p0_ws2)
    patch api_v1_incident_url(ws2_incident),
      params: { name: "Hack" }.to_json,
      headers: api_headers
    assert_response :not_found
  end

  # Error format

  test "error responses include request_id" do
    get api_v1_incident_url("nonexistent-id"), headers: api_headers
    assert_response :not_found

    error = json_response["error"]
    assert_equal "not_found", error["type"]
    assert_not_nil error["request_id"]
  end
end
