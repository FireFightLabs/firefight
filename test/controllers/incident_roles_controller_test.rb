require "test_helper"

class IncidentRolesControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents, :incident_roles,
           :incident_role_assignments

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)
  end

  test "create appends the role last" do
    post incident_roles_url, params: { name: "Scribe" }
    assert_response :redirect

    role = IncidentRole.find_by!(name: "Scribe", workspace: @workspace)
    assert_equal @workspace.incident_roles.maximum(:position), role.position
  end

  test "create with a blank name re-renders settings with errors" do
    post incident_roles_url, params: { name: "" }
    assert_response :redirect
    assert_not IncidentRole.exists?(name: "", workspace: @workspace)
  end

  test "update renames without touching the slug" do
    role = incident_roles(:communications_lead_ws1)

    patch incident_role_url(role), params: { name: "Comms Lead" }

    assert_equal "Comms Lead", role.reload.name
    assert_equal "communications_lead", role.slug
  end

  test "destroy refuses the built-in lead role" do
    role = incident_roles(:incident_lead_ws1)

    assert_no_difference -> { IncidentRole.count } do
      delete incident_role_url(role)
    end
    assert_match(/built in/, flash[:alert])
  end

  test "disable refuses the built-in lead role" do
    role = incident_roles(:incident_lead_ws1)

    patch disable_incident_role_url(role)

    assert_nil role.reload.deleted_at
    assert_match(/built in/, flash[:alert])
  end

  test "destroy refuses a role that is assigned and names the count" do
    role = incident_roles(:incident_lead_ws1)
    role.update!(slug: "not_built_in")
    assert_predicate role.incident_role_assignments.count, :positive?

    assert_no_difference -> { IncidentRole.count } do
      delete incident_role_url(role)
    end
    assert_match(/in use by #{role.incident_role_assignments.count} incident/, flash[:alert])
  end

  test "destroy succeeds for an unassigned role" do
    post incident_roles_url, params: { name: "Scribe" }
    role = IncidentRole.find_by!(name: "Scribe", workspace: @workspace)

    assert_difference -> { IncidentRole.count }, -1 do
      delete incident_role_url(role)
    end
    assert_equal "Scribe was deleted.", flash[:notice]
  end

  test "disable and enable each confirm with a notice" do
    role = incident_roles(:communications_lead_ws1)

    patch disable_incident_role_url(role)
    assert_not_nil role.reload.deleted_at
    assert_equal "Communications Lead was disabled.", flash[:notice]

    patch enable_incident_role_url(role)
    assert_nil role.reload.deleted_at
    assert_equal "Communications Lead was enabled.", flash[:notice]
  end

  test "reorder rewrites positions" do
    reversed = @workspace.incident_roles.ordered.to_a.reverse

    patch reorder_incident_roles_url, params: { ordered_ids: reversed.map(&:id) }
    assert_response :redirect

    result = @workspace.incident_roles.ordered.to_a
    assert_equal reversed.map(&:id), result.map(&:id)
    assert_equal (1..result.size).to_a, result.map(&:position)
    assert_equal "Role order updated.", flash[:notice]
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
