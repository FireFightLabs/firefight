require "test_helper"

class IncidentTypesControllerTest < ActionDispatch::IntegrationTest
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

  test "create with a blank name re-renders settings with errors" do
    post incident_types_url(format: :html), params: { name: "" }
    assert_response :redirect
    assert_not IncidentType.exists?(name: "", workspace: @workspace)
  end

  test "destroy hard-deletes a type no incident uses" do
    post incident_types_url(format: :html), params: { name: "Ephemeral" }
    type = IncidentType.find_by!(name: "Ephemeral", workspace: @workspace)

    assert_difference -> { IncidentType.count }, -1 do
      delete incident_type_url(type)
    end
    assert_response :redirect
    assert_not IncidentType.exists?(type.id)
  end

  test "destroy refuses a type in use and names the count" do
    type = incident_types(:service_outage_ws1)
    incidents(:active_critical_ws1).update!(incident_type: type)

    assert_no_difference -> { IncidentType.count } do
      delete incident_type_url(type)
    end
    assert_match(/in use by 1 incident/, flash[:alert])
  end

  test "disable then enable round-trips a type and confirms each way" do
    type = incident_types(:service_outage_ws1)

    patch disable_incident_type_url(type)
    assert_not_nil type.reload.deleted_at
    assert_equal "Service Outage was disabled.", flash[:notice]

    patch enable_incident_type_url(type)
    assert_nil type.reload.deleted_at
    assert_equal "Service Outage was enabled.", flash[:notice]
  end

  test "reorder rewrites positions" do
    reversed = @workspace.incident_types.ordered.to_a.reverse

    patch reorder_incident_types_url, params: { ordered_ids: reversed.map(&:id) }
    assert_response :redirect

    result = @workspace.incident_types.ordered.to_a
    assert_equal reversed.map(&:id), result.map(&:id)
    assert_equal (1..result.size).to_a, result.map(&:position)
    assert_equal "Type order updated.", flash[:notice]
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
