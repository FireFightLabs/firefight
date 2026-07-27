require "test_helper"

class IncidentSeveritiesControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)
  end

  test "create appends the severity last and makes it the least severe" do
    post incident_severities_url, params: { name: "Brand New" }
    assert_response :redirect

    ordered = @workspace.incident_severities.ordered
    severity = IncidentSeverity.find_by!(name: "Brand New", workspace: @workspace)

    assert_equal severity, ordered.last
    assert_equal ordered.count, severity.position
    assert_equal 1, severity.rank
  end

  test "create renumbers every rank from the resulting order" do
    post incident_severities_url, params: { name: "Brand New" }

    ordered = @workspace.incident_severities.ordered.to_a
    expected = (1..ordered.size).to_a.reverse

    assert_equal expected, ordered.map(&:rank)
    assert_equal (1..ordered.size).to_a, ordered.map(&:position)
  end

  test "create with a blank name re-renders settings with errors" do
    post incident_severities_url, params: { name: "" }
    assert_response :redirect
  end

  test "reorder rewrites positions and derives rank from the new order" do
    ordered = @workspace.incident_severities.ordered.to_a
    reversed = ordered.reverse

    patch reorder_incident_severities_url, params: { ordered_ids: reversed.map(&:id) }
    assert_response :redirect

    result = @workspace.incident_severities.ordered.to_a
    assert_equal reversed.map(&:id), result.map(&:id)
    assert_equal (1..result.size).to_a, result.map(&:position)
    assert_equal (1..result.size).to_a.reverse, result.map(&:rank)
  end

  test "reorder keeps severities missing from the payload at the end" do
    ordered = @workspace.incident_severities.ordered.to_a
    partial = [ ordered.last ]

    patch reorder_incident_severities_url, params: { ordered_ids: partial.map(&:id) }

    result = @workspace.incident_severities.ordered.to_a
    assert_equal ordered.last.id, result.first.id
    assert_equal ordered.size, result.size
  end

  test "reorder ignores ids from another workspace" do
    foreign = incident_severities(:p0_ws2)
    ordered = @workspace.incident_severities.ordered.to_a

    patch reorder_incident_severities_url, params: { ordered_ids: [ foreign.id ] + ordered.map(&:id) }

    assert_equal ordered.map(&:id), @workspace.incident_severities.ordered.map(&:id)
    assert_equal 1, foreign.reload.position
  end

  test "destroy alerts when severity is in use and names the incident count" do
    severity_in_use = incident_severities(:critical_ws1)
    count = severity_in_use.incidents.count

    assert_no_difference -> { IncidentSeverity.count } do
      delete incident_severity_url(severity_in_use)
    end
    assert_response :redirect
    assert_match(/in use by #{count} incident/, flash[:alert])
  end

  test "destroy refuses the default severity even when unused" do
    default_severity = incident_severities(:minor_ws1)
    default_severity.incidents.update_all(incident_severity_id: incident_severities(:major_ws1).id)

    assert_no_difference -> { IncidentSeverity.count } do
      delete incident_severity_url(default_severity)
    end
    assert_response :redirect
    assert_match(/default severity/, flash[:alert])
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
