require "test_helper"

class IncidentStatusesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)
  end

  test "create appends the status last within the workspace" do
    post incident_statuses_url, params: {
      name: "Mitigating", lifecycle_stage_key: IncidentLifecycleStage::ACTIVE
    }
    assert_response :redirect

    status = IncidentStatus.find_by!(name: "Mitigating", workspace: @workspace)
    assert_equal @workspace.incident_statuses.maximum(:position), status.position
  end

  test "create with a blank name re-renders settings with errors" do
    post incident_statuses_url, params: {
      name: "", lifecycle_stage_key: IncidentLifecycleStage::ACTIVE
    }
    assert_response :redirect
    assert_not IncidentStatus.exists?(name: "", workspace: @workspace)
  end

  test "destroy refuses a status in use and names the count" do
    status = incident_statuses(:investigating_ws1)
    status.update!(is_default: false)
    count = status.incidents.count
    assert count.positive?

    assert_no_difference -> { IncidentStatus.count } do
      delete incident_status_url(status)
    end
    assert_match(/in use by #{count} incident/, flash[:alert])
  end

  test "destroy refuses the default status" do
    status = incident_statuses(:investigating_ws1)
    assert status.is_default

    assert_no_difference -> { IncidentStatus.count } do
      delete incident_status_url(status)
    end
    assert_match(/default status/, flash[:alert])
  end

  test "destroy refuses the only enabled status in a stage" do
    status = incident_statuses(:resolved_ws1)
    status.incidents.update_all(incident_status_id: incident_statuses(:identified_ws1).id)
    assert_predicate status.reload, :last_enabled_in_stage?

    assert_no_difference -> { IncidentStatus.count } do
      delete incident_status_url(status)
    end
    assert_match(/only enabled status/, flash[:alert])
  end

  test "destroy succeeds for an unused status with a sibling in its stage" do
    status = incident_statuses(:monitoring_ws1)
    status.incidents.update_all(incident_status_id: incident_statuses(:identified_ws1).id)

    assert_difference -> { IncidentStatus.count }, -1 do
      delete incident_status_url(status)
    end
  end

  test "disable refuses the only enabled status in a stage" do
    status = incident_statuses(:resolved_ws1)

    patch disable_incident_status_url(status)

    assert_nil status.reload.deleted_at
    assert_match(/only enabled status/, flash[:alert])
  end

  test "disable refuses the default status" do
    status = incident_statuses(:investigating_ws1)

    patch disable_incident_status_url(status)

    assert_nil status.reload.deleted_at
    assert_match(/has to stay enabled/, flash[:alert])
  end

  test "disable and enable each confirm with a notice" do
    status = incident_statuses(:monitoring_ws1)

    patch disable_incident_status_url(status)
    assert_equal "Monitoring was disabled.", flash[:notice]

    patch enable_incident_status_url(status)
    assert_equal "Monitoring was enabled.", flash[:notice]
  end

  test "reorder confirms with a notice" do
    active_stage = IncidentLifecycleStage.find_by!(key: IncidentLifecycleStage::ACTIVE)
    active = @workspace.incident_statuses.ordered.where(incident_lifecycle_stage: active_stage).to_a

    patch reorder_incident_statuses_url, params: {
      lifecycle_stage_key: IncidentLifecycleStage::ACTIVE,
      ordered_ids: active.reverse.map(&:id)
    }

    assert_equal "Status order updated.", flash[:notice]
  end

  test "make_default promotes a live status and demotes the incumbent" do
    incumbent = incident_statuses(:investigating_ws1)
    promoted = incident_statuses(:identified_ws1)

    patch make_default_incident_status_url(promoted)

    assert promoted.reload.is_default
    assert_not incumbent.reload.is_default
    assert_equal 1, @workspace.incident_statuses.where(is_default: true).count
  end

  test "make_default refuses a closed-stage status" do
    incumbent = incident_statuses(:investigating_ws1)
    closed = incident_statuses(:resolved_ws1)

    patch make_default_incident_status_url(closed)

    assert_not closed.reload.is_default
    assert incumbent.reload.is_default
    assert_match(/has to start in triage or active/, flash[:alert])
  end

  test "make_default refuses a disabled status" do
    status = incident_statuses(:identified_ws1)
    status.update!(deleted_at: Time.current)

    patch make_default_incident_status_url(status)

    assert_not status.reload.is_default
    assert_match(/disabled/, flash[:alert])
  end

  test "reorder rewrites positions inside a stage and leaves other stages put" do
    active_stage = IncidentLifecycleStage.find_by!(key: IncidentLifecycleStage::ACTIVE)
    active = @workspace.incident_statuses.ordered.where(incident_lifecycle_stage: active_stage).to_a
    closed_before = @workspace.incident_statuses.ordered
      .where.not(incident_lifecycle_stage: active_stage).map(&:id)

    patch reorder_incident_statuses_url, params: {
      lifecycle_stage_key: IncidentLifecycleStage::ACTIVE,
      ordered_ids: active.reverse.map(&:id)
    }
    assert_response :redirect

    result = @workspace.incident_statuses.ordered.where(incident_lifecycle_stage: active_stage).map(&:id)
    assert_equal active.reverse.map(&:id), result

    closed_after = @workspace.incident_statuses.ordered
      .where.not(incident_lifecycle_stage: active_stage).map(&:id)
    assert_equal closed_before, closed_after

    all_positions = @workspace.incident_statuses.ordered.map(&:position)
    assert_equal (1..all_positions.size).to_a, all_positions
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
