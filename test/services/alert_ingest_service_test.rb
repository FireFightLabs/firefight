require "test_helper"

class AlertIngestServiceTest < ActiveSupport::TestCase
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

  test "routing records which rule matched" do
    policy = routing_policy!({ "action" => AlertIngestService::ACTION_DROP },
                             conditions: [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "checkout" ] } ])
    rule = policy.policy_rules.find_by!(priority: 1)

    alert = @service.ingest(firing_fields, {})

    assert_equal rule, alert.matched_policy_rule
  end

  test "unmatched alerts record no matched rule" do
    routing_policy!({ "action" => AlertIngestService::ACTION_DROP },
                    conditions: [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "other" ] } ])

    alert = @service.ingest(firing_fields, {})

    assert_equal Alert::ROUTING_UNMATCHED, alert.routing_state
    assert_nil alert.matched_policy_rule
  end

  test "notify_only posts the digest to the outcome channel" do
    routing_policy!({ "action" => AlertIngestService::ACTION_NOTIFY_ONLY, "notify" => { "type" => PolicyRule::AlertRoutingOutcome::TARGET_CHANNEL, "channel_id" => "C999" } })
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
    routing_policy!({ "action" => AlertIngestService::ACTION_NOTIFY_ONLY, "notify" => { "type" => PolicyRule::AlertRoutingOutcome::TARGET_CHANNEL, "channel_id" => "C999" } })
    stub_post_message
    stub_update_message

    alert = @service.ingest(firing_fields, {})
    # channel_id stores the conversation Slack resolved (matters for DMs)
    assert alert.channel_id.present?
    alert.update!(last_notified_at: 2.minutes.ago)

    refired = @service.ingest(firing_fields, {})
    assert_equal alert.id, refired.id
    assert refired.last_notified_at > 1.minute.ago, "refire should update the digest message"

    resolved = @service.ingest(firing_fields("status" => Alert::STATUS_RESOLVED), {})
    assert_equal Alert::STATUS_RESOLVED, resolved.status
  end

  test "route on an already-routed alert is a no-op (CAS)" do
    routing_policy!({ "action" => AlertIngestService::ACTION_AUTO_CREATE })

    alert = @service.ingest(firing_fields, {})
    assert_equal Alert::ROUTING_ROUTED, alert.routing_state
    matched_rule = alert.matched_policy_rule

    @service.route(alert.reload)

    assert_equal 1, Incident.where(source: Incident::SOURCE_ALERT).count
    assert_equal matched_rule, alert.reload.matched_policy_rule
  end

  test "refire inside the notify interval makes no Slack call" do
    routing_policy!({ "action" => AlertIngestService::ACTION_NOTIFY_ONLY, "notify" => { "type" => PolicyRule::AlertRoutingOutcome::TARGET_CHANNEL, "channel_id" => "C999" } })
    stub_post_message

    alert = @service.ingest(firing_fields, {})
    notified_at = alert.reload.last_notified_at
    assert notified_at.present?

    Slack::WorkspaceAdapter.any_instance.expects(:update_alert_message).never
    refired = @service.ingest(firing_fields, {})

    assert_equal alert.id, refired.id
    assert_equal notified_at, refired.last_notified_at
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

  test "notify_only can target a person via DM" do
    member = workspace_memberships(:alice_workspace_one)
    routing_policy!({ "action" => AlertIngestService::ACTION_NOTIFY_ONLY, "notify" => { "type" => PolicyRule::AlertRoutingOutcome::TARGET_MEMBER, "member_id" => member.id } })
    stub_post_message

    alert = @service.ingest(firing_fields, {})

    assert_equal Alert::ROUTING_ROUTED, alert.routing_state
    assert alert.channel_message_id.present?
    assert alert.channel_id.present?
  end

  test "auto_create with owning-team invite resolves members into workflow context" do
    manager = workspace_memberships(:alice_workspace_one)
    team = catalog_entries(:platform_team)
    team.update_column(:attributes, { "manager" => manager.id })
    routing_policy!({
      "action" => AlertIngestService::ACTION_AUTO_CREATE,
      "invite" => [ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM, "of" => "service" } ]
    })

    alert = @service.ingest(firing_fields("service" => "auth_service"), {})

    workflow = SolidWorkflow::Workflow.find_by!(subject_id: alert.incident.id)
    assert_equal alert.incident.id, workflow.subject_id
    assert_equal [ manager.id ], workflow.context["invite_membership_ids"]
  end

  test "unresolvable invite targets soft-fail onto the attach event" do
    routing_policy!({
      "action" => AlertIngestService::ACTION_AUTO_CREATE,
      "invite" => [ { "type" => PolicyRule::AlertRoutingOutcome::TARGET_OWNING_TEAM, "of" => "service" } ]
    })

    alert = @service.ingest(firing_fields("service" => "not-in-catalog"), {})

    assert alert.incident.present?, "incident must be created despite resolution misses"
    event = alert.incident.incident_events.find_by!(event_type: IncidentEvent::ALERT_ATTACHED)
    assert event.metadata["unresolved_targets"].any?
  end

  test "custom fingerprint fields change what dedups together" do
    @source.update!(config: { "fingerprint_fields" => [ "service" ] })
    routing_policy!({ "action" => AlertIngestService::ACTION_DROP })

    first = @service.ingest(firing_fields("title" => "One"), {})
    second = @service.ingest(firing_fields("title" => "Completely different"), {})

    assert_equal first.id, second.id
    assert_equal 2, second.reload.event_count
  end

  test "a zero flap window disables reopening" do
    @source.update!(config: { "flap_window_minutes" => 0 })
    routing_policy!({ "action" => AlertIngestService::ACTION_DROP })
    first = @service.ingest(firing_fields("external_id" => "e1"), {})
    @service.ingest(firing_fields("external_id" => "e1", "status" => Alert::STATUS_RESOLVED), {})

    fresh = @service.ingest(firing_fields("external_id" => "e2"), {})

    assert_not_equal first.id, fresh.id
  end

  test "grouping window and content match fields come from the policy domain_config" do
    routing_policy!({ "action" => AlertIngestService::ACTION_AUTO_CREATE },
                    domain_config: { "grouping_window_minutes" => 30, "content_match_fields" => [ "environment" ] })

    first = @service.ingest(firing_fields("external_id" => "e1", "environment" => "prod", "service" => "a"), {})
    second = @service.ingest(firing_fields("external_id" => "e2", "environment" => "prod", "service" => "b", "title" => "Other"), {})

    assert_equal first.incident, second.incident
    group = AlertGroup.find_by!(incident: first.incident)
    assert_in_delta 30.minutes.from_now.to_i, group.window_expires_at.to_i, 10
  end

  test "losing the open-fingerprint insert race folds into the winner" do
    routing_policy!({ "action" => AlertIngestService::ACTION_DROP })
    winner, created = @service.send(:persist, firing_fields("external_id" => "a"), {}, "fp-1", Time.current)
    assert created

    loser, loser_created = @service.send(:persist, firing_fields("external_id" => "b"), {}, "fp-1", Time.current)

    assert_not loser_created
    assert_equal winner.id, loser.id
    assert_equal 2, loser.reload.event_count
    assert_equal 1, @source.alerts.count
  end

  test "byte-identical redelivery neither re-counts nor re-routes" do
    routing_policy!({ "action" => AlertIngestService::ACTION_DROP })
    first = @service.ingest(firing_fields("external_id" => "dup-1", "fingerprint" => "fp-a"), {})
    first.update!(status: Alert::STATUS_RESOLVED, resolved_at: 1.hour.ago, last_seen_at: 1.hour.ago)

    again = @service.ingest(firing_fields("external_id" => "dup-1", "fingerprint" => "fp-a"), {})

    assert_equal first.id, again.id
    assert_equal 1, again.reload.event_count
  end

  test "flap reopen onto a closed incident detaches and re-routes" do
    routing_policy!({ "action" => AlertIngestService::ACTION_AUTO_CREATE })
    alert = @service.ingest(firing_fields, {})
    incident = alert.incident
    incident.update_column(:incident_status_id, incident_statuses(:resolved_ws1).id)
    @service.ingest(firing_fields("status" => Alert::STATUS_RESOLVED), {})

    reopened = @service.ingest(firing_fields, {})

    assert_equal alert.id, reopened.id
    assert_not_equal incident.id, reopened.incident&.id
    assert_equal Alert::ROUTING_ROUTED, reopened.routing_state
  end

  test "sweep retry of notify_only never double-posts the digest" do
    routing_policy!({ "action" => AlertIngestService::ACTION_NOTIFY_ONLY, "notify" => { "type" => PolicyRule::AlertRoutingOutcome::TARGET_CHANNEL, "channel_id" => "C999" } })
    stub_post_message
    alert = @service.ingest(firing_fields, {})
    assert alert.channel_message_id.present?

    # A partial routing failure leaves the alert pending with the digest
    # already posted. The sweep's retry must not post again.
    alert.update!(routing_state: Alert::ROUTING_PENDING)
    Slack::WorkspaceAdapter.any_instance.expects(:post_alert_message).never
    @service.route(alert.reload)

    assert_equal Alert::ROUTING_ROUTED, alert.reload.routing_state
  end

  test "repeated routing failures escalate to the failed state" do
    routing_policy!({ "action" => AlertIngestService::ACTION_AUTO_CREATE, "severity_id" => SecureRandom.uuid })
    @workspace.incident_severities.update_all(is_default: false)

    alert = @service.ingest(firing_fields, {})
    assert_equal Alert::ROUTING_PENDING, alert.reload.routing_state
    assert_equal 1, alert.routing_attempts

    (Alert::MAX_ROUTING_ATTEMPTS - 1).times { @service.route(alert.reload) }

    assert_equal Alert::ROUTING_FAILED, alert.reload.routing_state
  end

  test "a failed digest attempt still stamps last_notified_at" do
    routing_policy!({ "action" => AlertIngestService::ACTION_NOTIFY_ONLY, "notify" => { "type" => PolicyRule::AlertRoutingOutcome::TARGET_CHANNEL, "channel_id" => "C999" } })
    stub_post_message
    alert = @service.ingest(firing_fields, {})
    alert.update!(last_notified_at: 5.minutes.ago)

    Slack::WorkspaceAdapter.any_instance.stubs(:update_alert_message).raises(AdapterError::NotInChannel.new("not_in_channel"))
    @service.ingest(firing_fields, {})

    assert alert.reload.last_notified_at > 1.minute.ago
  end

  test "routing failure leaves the alert pending for the sweep" do
    routing_policy!({ "action" => AlertIngestService::ACTION_AUTO_CREATE })
    Policy.any_instance.stubs(:evaluate).raises(StandardError, "boom")

    alert = @service.ingest(firing_fields, {})

    assert_equal Alert::ROUTING_PENDING, alert.routing_state
  end

  test "a failure after the outcome committed leaves the alert routed, so the sweep cannot apply it twice" do
    routing_policy!({ "action" => AlertIngestService::ACTION_AUTO_CREATE })
    AlertIngestService.any_instance.stubs(:apply_outcome).returns(-> { raise StandardError, "channel post blew up" })

    alert = @service.ingest(firing_fields, {})

    assert_equal Alert::ROUTING_ROUTED, alert.reload.routing_state
    assert_equal 0, alert.routing_attempts
    assert alert.routed_at.present?
  end

  test "a flap reopen clears every trace of the previous routing episode" do
    routing_policy!({ "action" => AlertIngestService::ACTION_AUTO_CREATE })
    alert = @service.ingest(firing_fields, {})
    alert.incident.update_column(:incident_status_id, incident_statuses(:resolved_ws1).id)
    first_routed_at = alert.routed_at
    @service.ingest(firing_fields("status" => Alert::STATUS_RESOLVED), {})
    travel 1.minute

    reopened = @service.ingest(firing_fields, {})

    assert_not_equal first_routed_at, reopened.routed_at
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
