require "test_helper"

class AlertsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @source = @workspace.alert_sources.create!(name: "Mixpanel", provider: AlertSource::PROVIDER_MIXPANEL)
    @alert = @source.alerts.create!(workspace: @workspace, external_id: "e1", fingerprint: "alert:1:2026", fields: { "title" => "Signups dropped" },
                                    received_at: 1.hour.ago, last_seen_at: 1.hour.ago)
  end

  test "resolving a firing alert by hand takes the tool's resolve path, says so, and the activity log names who did it" do
    sign_in(users(:alice), @workspace)

    patch resolve_alert_url(@alert)

    assert_redirected_to settings_alerts_path
    assert_equal "Signups dropped was resolved.", flash[:notice]
    assert_equal Alert::STATUS_RESOLVED, @alert.reload.status
    assert @alert.resolved_at.present?
    assert @workspace.ability_invocations.exists?(
      principal: workspace_memberships(:alice_workspace_one), action_key: "alerts.update", source: AbilityGateway::SOURCE_WEB,
      decision: Ability::Invocation::DECISION_ALLOW, outcome: Ability::Invocation::OUTCOME_SUCCESS
    )
  end

  test "an alert already resolved is refused with the reason" do
    @alert.resolve!
    sign_in(users(:alice), @workspace)

    patch resolve_alert_url(@alert)

    assert_equal "Signups dropped is already resolved.", flash[:alert]
  end

  test "like a resolve from the tool, it reaches the incident's timeline and updates the alert's message" do
    incident = incidents(:active_critical_ws1)
    @alert.update!(incident: incident, channel_id: "C12345678")
    stub_post_message
    sign_in(users(:alice), @workspace)

    patch resolve_alert_url(@alert)

    assert incident.incident_events.exists?(event_type: IncidentEvent::ALERT_RESOLVED)
    assert @alert.reload.last_notified_at.present?
  end

  test "a member without a grant to manage alerts cannot resolve one" do
    sign_in(users(:bob), @workspace)

    patch resolve_alert_url(@alert)

    assert_predicate @alert.reload, :firing?
  end

  test "another workspace's alert is not found" do
    sign_in(users(:alice), @workspace)
    other = workspaces(:slack_workspace_two).alert_sources.create!(name: "Other", provider: AlertSource::PROVIDER_GENERIC)
    foreign = other.alerts.create!(workspace: other.workspace, external_id: "x", fingerprint: "x", received_at: Time.current, last_seen_at: Time.current)

    patch resolve_alert_url(foreign)

    assert_response :not_found
    assert_predicate foreign.reload, :firing?
  end
end
