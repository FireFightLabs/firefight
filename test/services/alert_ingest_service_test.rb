require "test_helper"

class AlertIngestServiceTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incident_types, :incident_roles,
           :incidents, :incident_events

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @source = AlertSource.create!(workspace: @workspace, name: "Monitoring", provider: AlertSource::PROVIDER_GENERIC)
    @service = AlertIngestService.new(@source)
    stub_successful_slack_workflow
  end

  def firing_fields(overrides = {})
    { "title" => "Checkout 504s", "service" => "checkout", "status" => Alert::STATUS_FIRING }.merge(overrides)
  end

  def routing_policy!(outcome, conditions: [], domain_config: {})
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing", domain_config: domain_config)
    policy.policy_rules.create!(priority: 1, conditions: conditions, outcome: outcome)
    policy
  end

  test "firing with no policy persists the alert as unmatched" do
    alert = @service.ingest(firing_fields, { "raw" => true })

    assert_equal Alert::ROUTING_UNMATCHED, alert.routing_state
    assert_nil alert.incident
    assert_equal 1, alert.event_count
  end

  test "repeat firing dedups into one row via fingerprint" do
    first = @service.ingest(firing_fields, {})
    second = @service.ingest(firing_fields("external_id" => "different-delivery"), {})

    assert_equal first.id, second.id
    assert_equal 2, second.event_count
    assert_equal 1, @source.alerts.count
  end

  test "refire shortly after resolve reopens the same alert (flap)" do
    alert = @service.ingest(firing_fields, {})
    alert.resolve!

    reopened = @service.ingest(firing_fields, {})

    assert_equal alert.id, reopened.id
    assert reopened.firing?
    assert_equal 2, reopened.event_count
  end

  test "resolved event resolves the open alert and records an incident event" do
    routing_policy!({ "action" => AlertIngestService::ACTION_ATTACH })
    incident = incidents(:active_critical_ws1)
    AlertGroup.create!(workspace: @workspace, incident: incident,
                       content_signature: AlertGroup.signature_for(firing_fields, [ "service" ]),
                       window_expires_at: 10.minutes.from_now)
    stub_post_message
    stub_update_message

    alert = @service.ingest(firing_fields, {})
    assert_equal incident, alert.incident

    resolved = @service.ingest(firing_fields("status" => Alert::STATUS_RESOLVED), {})

    assert_equal Alert::STATUS_RESOLVED, resolved.status
    assert incident.incident_events.find_by!(event_type: IncidentEvent::ALERT_RESOLVED)
  end

  test "drop outcome routes without creating anything" do
    routing_policy!({ "action" => AlertIngestService::ACTION_DROP })

    alert = @service.ingest(firing_fields, {})

    assert_equal Alert::ROUTING_ROUTED, alert.routing_state
    assert_nil alert.incident
  end

  test "notify_only posts the digest to the outcome channel" do
    routing_policy!({ "action" => AlertIngestService::ACTION_NOTIFY_ONLY, "channel" => "C999" })
    stub_post_message

    alert = @service.ingest(firing_fields, {})

    assert_equal Alert::ROUTING_ROUTED, alert.routing_state
    assert alert.channel_message_id.present?
    assert_nil alert.incident
  end

  test "auto_create_incident creates the incident, attaches, groups, records the event" do
    routing_policy!({ "action" => AlertIngestService::ACTION_AUTO_CREATE })

    alert = @service.ingest(firing_fields, {})

    incident = alert.incident
    assert incident.present?
    assert_equal Incident::SOURCE_ALERT, incident.source
    assert_equal "Checkout 504s", incident.name
    assert incident.incident_events.find_by!(event_type: IncidentEvent::ALERT_ATTACHED)
    assert AlertGroup.find_by!(incident: incident)
    assert_equal Alert::ROUTING_ROUTED, alert.routing_state
  end

  test "auto_create uses outcome severity override, else source severity map" do
    severities = @workspace.incident_severities.active.order(:rank).to_a
    override = severities.first
    routing_policy!({ "action" => AlertIngestService::ACTION_AUTO_CREATE, "severity_id" => override.id })

    alert = @service.ingest(firing_fields, {})

    assert_equal override, alert.incident.incident_severity
  end

  test "storm of related alerts groups into one incident" do
    routing_policy!({ "action" => AlertIngestService::ACTION_AUTO_CREATE })

    first = @service.ingest(firing_fields, { "event" => 1 })
    second = @service.ingest(firing_fields("title" => "Checkout latency p99"), { "event" => 2 })

    assert_not_equal first.id, second.id
    assert_equal first.incident_id, second.incident_id
    assert_equal 1, Incident.where(source: Incident::SOURCE_ALERT).count
  end

  test "attach_to_incident without an open group routes without creating an incident" do
    routing_policy!({ "action" => AlertIngestService::ACTION_ATTACH })

    alert = @service.ingest(firing_fields, {})

    assert_equal Alert::ROUTING_ROUTED, alert.routing_state
    assert_nil alert.incident
    assert_equal 0, Incident.where(source: Incident::SOURCE_ALERT).count
  end

  test "batched items without external ids persist as distinct alerts" do
    shared_payload = { "alerts" => [ { "n" => 1 }, { "n" => 2 } ] }

    first = @service.ingest(firing_fields("title" => "Pod A crash", "service" => "pod-a"), shared_payload)
    second = @service.ingest(firing_fields("title" => "Pod B crash", "service" => "pod-b"), shared_payload)

    assert_not_equal first.id, second.id
    assert_equal 2, @source.alerts.count
  end

  test "notify_only digest updates in place on refire and resolve" do
    routing_policy!({ "action" => AlertIngestService::ACTION_NOTIFY_ONLY, "channel" => "C999" })
    stub_post_message
    stub_update_message

    alert = @service.ingest(firing_fields, {})
    assert_equal "C999", alert.channel_id
    alert.update!(last_notified_at: 2.minutes.ago)

    refired = @service.ingest(firing_fields, {})
    assert_equal alert.id, refired.id
    assert refired.last_notified_at > 1.minute.ago, "refire should update the digest message"

    resolved = @service.ingest(firing_fields("status" => Alert::STATUS_RESOLVED), {})
    assert_equal Alert::STATUS_RESOLVED, resolved.status
  end

  test "source-scoped policy takes precedence over the workspace-wide fallback" do
    routing_policy!({ "action" => AlertIngestService::ACTION_AUTO_CREATE })
    scoped = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Scoped", scoped_to: @source)
    scoped.policy_rules.create!(priority: 1, conditions: [], outcome: { "action" => AlertIngestService::ACTION_DROP })

    alert = @service.ingest(firing_fields, {})

    assert_equal Alert::ROUTING_ROUTED, alert.routing_state
    assert_nil alert.incident, "scoped drop rule should win over workspace auto-create"
  end

  test "disabled source-scoped policy falls back to the workspace-wide policy" do
    routing_policy!({ "action" => AlertIngestService::ACTION_DROP })
    scoped = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Scoped", scoped_to: @source, enabled: false)
    scoped.policy_rules.create!(priority: 1, conditions: [], outcome: { "action" => AlertIngestService::ACTION_AUTO_CREATE })

    alert = @service.ingest(firing_fields, {})

    assert_equal Alert::ROUTING_ROUTED, alert.routing_state
    assert_nil alert.incident
  end

  test "routing failure leaves the alert pending for the sweep" do
    routing_policy!({ "action" => AlertIngestService::ACTION_AUTO_CREATE })
    Policy.any_instance.stubs(:evaluate).raises(StandardError, "boom")

    alert = @service.ingest(firing_fields, {})

    assert_equal Alert::ROUTING_PENDING, alert.routing_state
  end

  test "unmatched conditions mark the alert unmatched" do
    routing_policy!(
      { "action" => AlertIngestService::ACTION_AUTO_CREATE },
      conditions: [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "billing" ] } ]
    )

    alert = @service.ingest(firing_fields, {})

    assert_equal Alert::ROUTING_UNMATCHED, alert.routing_state
  end
end
