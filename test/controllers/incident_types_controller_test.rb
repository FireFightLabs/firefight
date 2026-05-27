require "test_helper"

class IncidentTypesControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)
  end

  test "create assigns next position" do
    post incident_types_url(format: :html), params: { name: "Outage" }
    assert_response :redirect

    type = IncidentType.find_by!(name: "Outage", workspace: @workspace)
    assert type.position.positive?
  end

  test "destroy always soft-deletes via deleted_at, even with no incidents" do
    post incident_types_url(format: :html), params: { name: "Ephemeral" }
    type = IncidentType.find_by!(name: "Ephemeral", workspace: @workspace)

    delete incident_type_url(type)
    assert_response :redirect
    assert_not_nil type.reload.deleted_at
    assert IncidentType.exists?(type.id), "Should not hard-delete"
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
