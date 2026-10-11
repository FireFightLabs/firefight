require "test_helper"

# Once a hosted build's plan lapses, the workspace stays open to read and to work the incidents it already has, while
# every way of declaring a new one refuses with the backend's sentence and Halon stops.
class PlanLapseTest < ActionDispatch::IntegrationTest
  REASON = EntitlementsTestHelper::PlanBackend::LAPSED

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    @severity = @workspace.incident_severities.active.first
    sell_plan!(stage: :lapsed)
  end

  test "the dashboard and an existing incident stay readable, and every Declare button says why it waits" do
    sign_in(users(:alice), @workspace)

    get dashboard_path, headers: inertia_headers
    assert_response :success
    assert_equal REASON, inertia_props.dig("currentWorkspace", "incidentsBlockedReason")

    get incident_path(incidents(:active_critical_ws1)), headers: inertia_headers
    assert_response :success
  end

  test "declaring from the dashboard is refused with the reason" do
    sign_in(users(:alice), @workspace)

    assert_no_difference -> { @workspace.incidents.count } do
      post declare_incident_path, params: { answers: { name: "Checkout failing", severity: @severity.slug } }
    end

    assert_equal REASON, flash[:alert]
  end

  test "the public API answers 422 with the reason" do
    _, token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Pager", permissions: { "incidents" => %w[read create] }
    )

    assert_no_difference -> { @workspace.incidents.count } do
      post api_v1_incidents_url, headers: api_headers(token: token),
        params: { idempotency_key: SecureRandom.uuid, name: "Checkout failing", severity_id: @severity.id }.to_json
    end

    assert_response :unprocessable_entity
    assert_equal "incidents_blocked", json_response.dig("error", "type")
    assert_equal REASON, json_response.dig("error", "message")
  end

  test "the public API still reads the incidents already there" do
    _, token = create_service_key(workspace: @workspace, created_by: @membership, name: "Reader", permissions: { "incidents" => %w[read] })

    get api_v1_incidents_url, headers: api_headers(token: token)

    assert_response :success
  end

  test "the Slack declare command answers with the reason instead of opening the form" do
    WorkspaceAdapter.any_instance.expects(:open_modal).never

    response = Commands::DeclareIncident.execute(slack_command(Identifiers::SUBCOMMAND_NEW))

    assert_equal Command::EPHEMERAL, response[:response_type]
    assert_equal REASON, response[:text]
  end

  test "a bare /ff outside an incident answers with the reason too" do
    WorkspaceAdapter.any_instance.expects(:open_modal).never

    response = Commands::OpenHome.execute(slack_command(""))

    assert_equal REASON, response[:text]
  end

  test "a declare form already open in Slack is refused on submit with the reason under the name" do
    interaction = Interaction.new(
      platform: Platforms::SLACK, type: Interaction::VIEW_SUBMISSION, team_id: @workspace.platform_id, user_id: @membership.platform_user_id,
      values: {
        "field_name_block" => { "field_name_input" => { "value" => "Checkout failing" } },
        "field_severity_block" => { Identifiers::INCIDENT_CREATION_SEVERITY_SELECT => { "selected_option" => { "value" => @severity.slug } } },
        "field_visibility_block" => { "field_visibility_input" => { "selected_option" => { "value" => "public" } } }
      }
    )

    result = nil
    assert_no_difference -> { @workspace.incidents.count } do
      result = Interactions::IncidentCreationHandler.execute(interaction)
    end

    assert_equal "errors", result[:response_action]
    assert_equal [ REASON ], result[:errors].values
  end

  test "Halon stops with the same sentence" do
    assert_equal REASON, Investigation.unavailable_reason(@workspace) if defined?(FirefightAi)
    assert_not Entitlements.allows?(@workspace, Entitlements::AI)
  end

  test "an install someone runs themselves never holds incidents back" do
    Entitlements.reset_backend!

    assert_nil @workspace.incidents_blocked_reason
    assert_nil @workspace.access_blocked
  end

  private

  def slack_command(text)
    Command.new(
      platform: Platforms::SLACK, workspace_id: @workspace.id, user_id: @membership.platform_user_id, text: text,
      channel_id: "C99999999", trigger_id: "trigger", metadata: { command: "/ff" }
    )
  end
end
