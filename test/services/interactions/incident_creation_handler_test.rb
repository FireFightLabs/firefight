require "test_helper"

class Interactions::IncidentCreationHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "creates incident and starts workflow" do
    IncidentCreationWorkflow.stubs(:start!)

    payload = build_payload(
      severity: "critical",
      name: "DB Down",
      summary: "Primary DB offline",
      visibility: "public"
    )

    assert_difference "Incident.count", 1 do
      result = Interactions::IncidentCreationHandler.execute(payload)
      assert_nil result
    end

    incident = Incident.find_by!(name: "DB Down")
    assert_equal @workspace, incident.workspace
    assert_equal @member, incident.declared_by
    assert_equal "critical", incident.incident_severity.slug
    assert_equal "investigating", incident.incident_status.slug
    assert_equal "Primary DB offline", incident.summary
    assert_equal false, incident.is_private
  end

  test "sets is_private when visibility is private" do
    IncidentCreationWorkflow.stubs(:start!)

    payload = build_payload(visibility: "private")

    Interactions::IncidentCreationHandler.execute(payload)

    incident = Incident.find_by!(name: "Test Incident")
    assert incident.is_private
  end

  test "returns error for invalid severity" do
    payload = build_payload(severity: "nonexistent")

    result = Interactions::IncidentCreationHandler.execute(payload)

    assert_equal "errors", result[:response_action]
    assert result[:errors][:severity_block].present?
  end

  test "returns error for unknown workspace member" do
    payload = build_payload
    payload["user"]["id"] = "U_UNKNOWN"

    result = Interactions::IncidentCreationHandler.execute(payload)

    assert_equal "errors", result[:response_action]
  end

  private

  def build_payload(severity: "minor", name: "Test Incident", summary: "Test summary", visibility: "public")
    {
      "type" => "view_submission",
      "team" => { "id" => @workspace.platform_id },
      "user" => { "id" => @member.platform_user_id },
      "view" => {
        "callback_id" => Slack::Identifiers::INCIDENT_CREATION_MODAL,
        "state" => {
          "values" => {
            "name_block" => { "name_input" => { "value" => name } },
            "severity_block" => { "severity_select" => { "selected_option" => { "value" => severity } } },
            "summary_block" => { "summary_input" => { "value" => summary } },
            "visibility_block" => { "visibility_select" => { "selected_option" => { "value" => visibility } } }
          }
        }
      }
    }
  end
end
