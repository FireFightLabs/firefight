require "test_helper"

class Api::V1::IncidentsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incident_types, :incidents,
           :api_keys, :idempotency_keys

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @severity = @workspace.incident_severities.active.first
    @status = @workspace.incident_statuses.default_status
  end

  # ============================================================================
  # AUTHENTICATION
  # ============================================================================

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

  # ============================================================================
  # PERMISSIONS
  # ============================================================================

  test "returns 403 when key lacks create permission" do
    post api_v1_incidents_url,
      params: { idempotency_key: "test", name: "Test", severity_id: @severity.id }.to_json,
      headers: api_headers(token: "ff_test_read_only_token_12345678")
    assert_response :forbidden
  end

  # ============================================================================
  # INDEX
  # ============================================================================

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

  # ============================================================================
  # SHOW
  # ============================================================================

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

  test "returns 404 for incident from different workspace" do
    ws2_incident = incidents(:active_p0_ws2)
    get api_v1_incident_url(ws2_incident), headers: api_headers
    assert_response :not_found
  end

  # ============================================================================
  # CREATE
  # ============================================================================

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

  # ============================================================================
  # UPDATE
  # ============================================================================

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

  test "returns 404 when updating incident from different workspace" do
    ws2_incident = incidents(:active_p0_ws2)
    patch api_v1_incident_url(ws2_incident),
      params: { name: "Hack" }.to_json,
      headers: api_headers
    assert_response :not_found
  end

  # ============================================================================
  # ERROR FORMAT
  # ============================================================================

  test "error responses include request_id" do
    get api_v1_incident_url("nonexistent-id"), headers: api_headers
    assert_response :not_found

    error = json_response["error"]
    assert_equal "not_found", error["type"]
    assert_not_nil error["request_id"]
  end
end
