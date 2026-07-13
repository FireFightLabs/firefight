require "test_helper"

class Alerts::RoutingSweepJobTest < ActiveSupport::TestCase
  fixtures :workspaces, :incident_lifecycle_stages, :incident_statuses, :incident_severities

  test "routes stale pending alerts" do
    workspace = workspaces(:slack_workspace_one)
    source = AlertSource.create!(workspace: workspace, name: "Sweep source", provider: AlertSource::PROVIDER_GENERIC)
    policy = workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(priority: 1, conditions: [], outcome: { "action" => AlertIngestService::ACTION_DROP })

    stale = source.alerts.create!(
      workspace: workspace, external_id: "stale-1", fingerprint: "fp-1",
      received_at: 5.minutes.ago, last_seen_at: 5.minutes.ago
    )
    fresh = source.alerts.create!(
      workspace: workspace, external_id: "fresh-1", fingerprint: "fp-2",
      received_at: 10.seconds.ago, last_seen_at: 10.seconds.ago
    )

    Alerts::RoutingSweepJob.perform_now

    assert_equal Alert::ROUTING_ROUTED, stale.reload.routing_state
    assert_equal Alert::ROUTING_PENDING, fresh.reload.routing_state
  end
end
