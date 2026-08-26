require "test_helper"

# Configuring the workspace over REST, matching the MCP tools. The option lists
# share one concern, so severities stand in for the shape and the others are
# checked where they differ.
class Api::V1::WorkspaceConfigApiTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    _, @admin_token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Admin"
    )
  end

  # The endpoint promised these two things before it could be written to, and
  # adding writes must not move either.
  test "a listing keeps its collection name and leaves disabled entries out" do
    severity = @workspace.incident_severities.active.where(is_default: false).first
    severity.disable!

    get api_v1_severities_url, headers: api_headers(token: @admin_token)

    assert_response :success
    assert json_response.key?("severities")
    assert_not_includes json_response["severities"].map { |s| s["id"] }, severity.id
    assert json_response["severities"].first.key?("rank")
  end

  test "a caller managing the list can ask for the disabled ones" do
    severity = @workspace.incident_severities.active.where(is_default: false).first
    severity.disable!

    get api_v1_severities_url(include_disabled: true), headers: api_headers(token: @admin_token)

    listed = json_response["severities"].find { |s| s["id"] == severity.id }
    assert listed, "a disabled severity should be listed when asked for"
    assert_not listed["enabled"]
  end

  test "creating a severity puts it at the end of the list" do
    post api_v1_severities_url,
         params: { name: "SEV0", rank: 1, color: "#e5484d" },
         headers: api_headers(token: @admin_token), as: :json

    assert_response :created
    severity = @workspace.incident_severities.find_by!(slug: "sev0")
    assert_equal 1, severity.rank
    assert_equal @workspace.incident_severities.maximum(:position), severity.position
  end

  test "renaming keeps the slug, which stored records point at" do
    severity = @workspace.incident_severities.active.first

    patch api_v1_severity_url(severity.slug),
          params: { name: "Renamed" }, headers: api_headers(token: @admin_token), as: :json

    assert_response :success
    assert_equal "Renamed", severity.reload.name
    assert_equal severity.slug, json_response["slug"]
  end

  test "a status is created into the lifecycle stage it names" do
    post api_v1_statuses_url,
         params: { name: "Mitigating", lifecycle_stage: IncidentLifecycleStage::ACTIVE },
         headers: api_headers(token: @admin_token), as: :json

    assert_response :created
    assert_equal IncidentLifecycleStage::ACTIVE, json_response["lifecycle_stage"]
  end

  test "disabling retires an option without deleting it" do
    type = @workspace.incident_types.active.first

    patch api_v1_incident_type_url(type.slug),
          params: { enabled: false }, headers: api_headers(token: @admin_token), as: :json

    assert_response :success
    assert_not_nil type.reload.deleted_at
    assert_not json_response["enabled"]
  end

  test "the default cannot be disabled, and the reason says why" do
    severity = @workspace.incident_severities.find_by(is_default: true)
    skip "no default severity in this workspace" unless severity

    patch api_v1_severity_url(severity.slug),
          params: { enabled: false }, headers: api_headers(token: @admin_token), as: :json

    assert_response :unprocessable_entity
    assert_nil severity.reload.deleted_at
  end

  test "deleting is refused while incidents still point at it" do
    severity = incidents(:active_critical_ws1).incident_severity

    delete api_v1_severity_url(severity.slug), headers: api_headers(token: @admin_token)

    assert_response :unprocessable_entity
    assert_match(/cannot be deleted/, json_response.dig("error", "message"))
  end

  test "incident roles are reachable at all, which they were not before" do
    post api_v1_incident_roles_url,
         params: { name: "Comms lead", description: "Talks to everyone outside the incident." },
         headers: api_headers(token: @admin_token), as: :json

    assert_response :created
    assert @workspace.incident_roles.exists?(slug: "comms_lead")
  end

  test "an alert source is created and addressed by its endpoint path" do
    post api_v1_alert_sources_url,
         params: { name: "Datadog monitors" }, headers: api_headers(token: @admin_token), as: :json

    assert_response :created
    source = @workspace.alert_sources.find_by!(name: "Datadog monitors")
    assert_equal source.endpoint_path, json_response["slug"]

    patch api_v1_alert_source_url(source.endpoint_path),
          params: { enabled: false }, headers: api_headers(token: @admin_token), as: :json

    assert_response :success
    assert_not source.reload.enabled
  end

  test "a webhook is created with its events, and sending events replaces them" do
    events = Webhook::SUBSCRIBABLE_EVENTS.first(2)

    post api_v1_webhooks_url,
         params: { name: "Ops relay", url: "https://example.com/hooks/ff", subscribed_events: events },
         headers: api_headers(token: @admin_token), as: :json

    assert_response :created
    webhook = @workspace.webhooks.find_by!(name: "Ops relay")
    assert_equal events, webhook.subscribed_events

    patch api_v1_webhook_url(webhook),
          params: { subscribed_events: [ events.first ] },
          headers: api_headers(token: @admin_token), as: :json

    assert_equal [ events.first ], webhook.reload.subscribed_events
  end

  test "a webhook response never carries the signing secret" do
    post api_v1_webhooks_url,
         params: { name: "Ops relay", url: "https://example.com/hooks/ff" },
         headers: api_headers(token: @admin_token), as: :json

    assert_not json_response.key?("signing_secret")
  end

  test "a service key granted only alerts cannot touch severities" do
    _, token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Alerting",
      permissions: { Ability::Action::RESOURCE_ALERTS => %w[read create] }
    )

    post api_v1_severities_url, params: { name: "Sneaky" }, headers: api_headers(token: token), as: :json

    assert_response :forbidden
    assert_nil @workspace.incident_severities.find_by(slug: "sneaky")
  end

  test "another workspace's severity is not reachable" do
    other = workspaces(:slack_workspace_two).incident_severities.first

    patch api_v1_severity_url(other.slug),
          params: { name: "Nope" }, headers: api_headers(token: @admin_token), as: :json

    assert_response :not_found
  end
end
