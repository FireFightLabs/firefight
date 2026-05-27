require "test_helper"

class IncidentSeveritiesControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)
  end

  test "create assigns next position atomically" do
    post incident_severities_url, params: { name: "Brand New", rank: 99 }
    assert_response :redirect

    severity = IncidentSeverity.find_by!(name: "Brand New", workspace: @workspace)
    max = IncidentSeverity.where(workspace: @workspace).where.not(id: severity.id).maximum(:position)
    assert_equal max.to_i + 1, severity.position
  end

  test "create with invalid params re-renders settings with errors" do
    post incident_severities_url, params: { name: "Dup", rank: "nope" }
    assert_response :redirect
  end

  test "destroy alerts when severity is in use" do
    severity_in_use = incident_severities(:critical_ws1)

    assert_no_difference -> { IncidentSeverity.count } do
      delete incident_severity_url(severity_in_use)
    end
    assert_response :redirect
    assert_match(/in use/, flash[:alert])
  end

  test "destroy succeeds when severity is unused" do
    severity = current_workspace_severities.new(
      name: "Orphan", slug: "orphan", rank: 50
    )
    severity.save_in_position!

    assert_difference -> { IncidentSeverity.count }, -1 do
      delete incident_severity_url(severity)
    end
  end

  test "disable + enable toggle deleted_at" do
    severity = incident_severities(:critical_ws1)

    patch disable_incident_severity_url(severity)
    assert_response :redirect
    assert_not_nil severity.reload.deleted_at

    patch enable_incident_severity_url(severity)
    assert_response :redirect
    assert_nil severity.reload.deleted_at
  end

  private

  def current_workspace_severities
    @workspace.incident_severities
  end

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
