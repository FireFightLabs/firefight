require "test_helper"

class AlertSourcesControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)
  end

  test "create generates a source with credentials" do
    post alert_sources_url, params: { alert_source: { name: "Grafana prod" } }

    assert_redirected_to settings_alert_sources_path
    source = @workspace.alert_sources.find_by!(name: "Grafana prod")
    assert source.endpoint_path.present?
    assert source.secret_token.present?
  end

  test "update writes name, enabled, and a validated severity map" do
    source = @workspace.alert_sources.create!(name: "Old", provider: AlertSource::PROVIDER_GENERIC)
    severity = @workspace.incident_severities.active.first

    patch alert_source_url(source), params: {
      alert_source: {
        name: "Renamed",
        enabled: false,
        severity_map: { "Critical" => severity.id, "bogus" => "not-a-severity-id" }
      }
    }

    source.reload
    assert_equal "Renamed", source.name
    assert_not source.enabled
    assert_equal({ "critical" => severity.id }, source.config["severity_map"])
  end

  test "destroy removes the source" do
    source = @workspace.alert_sources.create!(name: "Gone", provider: AlertSource::PROVIDER_GENERIC)

    delete alert_source_url(source)

    assert_nil AlertSource.find_by(id: source.id)
  end

  test "cannot touch another workspace's source" do
    other = workspaces(:slack_workspace_two)
    source = other.alert_sources.create!(name: "Theirs", provider: AlertSource::PROVIDER_GENERIC)

    patch alert_source_url(source), params: { alert_source: { name: "Hijacked" } }

    assert_response :not_found
    assert_equal "Theirs", source.reload.name
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
