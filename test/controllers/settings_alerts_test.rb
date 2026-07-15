require "test_helper"

class SettingsAlertsTest < ActionDispatch::IntegrationTest
  include InertiaTestHelper

  fixtures :workspaces, :users, :workspace_memberships

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    @source = @workspace.alert_sources.create!(name: "Northflank", provider: AlertSource::PROVIDER_NORTHFLANK)
    @other_source = @workspace.alert_sources.create!(name: "Grafana", provider: AlertSource::PROVIDER_GENERIC)
  end

  test "lists recent alerts newest first with source and routing details" do
    old = create_alert(@source, external_id: "a1", title: "Disk full", last_seen_at: 2.hours.ago)
    recent = create_alert(@other_source, external_id: "a2", title: "Container crash", last_seen_at: 1.minute.ago,
                          routing_state: Alert::ROUTING_UNMATCHED)

    get settings_alerts_url, headers: inertia_headers

    assert_response :success
    alerts = inertia_props["alerts"]
    assert_equal [ recent.id, old.id ], alerts.map { |a| a["id"] }
    assert_equal "Grafana", alerts.first["sourceName"]
    assert_equal Alert::ROUTING_UNMATCHED, alerts.first["routingState"]
  end

  test "filters by source" do
    create_alert(@source, external_id: "a1", title: "Disk full")
    create_alert(@other_source, external_id: "a2", title: "Container crash")

    get settings_alerts_url(source_id: @source.id), headers: inertia_headers

    assert_response :success
    alerts = inertia_props["alerts"]
    assert_equal [ "Disk full" ], alerts.map { |a| a["title"] }
    assert_equal @source.id, inertia_props["sourceId"]
  end

  test "filters by matched rule and offers only the selected source's rules" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "NF routing", scoped_to: @source)
    rule = policy.policy_rules.create!(priority: 1, conditions: [],
                                       outcome: { "action" => AlertIngestService::ACTION_DROP })
    other_policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Default routing")
    other_policy.policy_rules.create!(priority: 1, conditions: [],
                                      outcome: { "action" => AlertIngestService::ACTION_DROP })

    matched = create_alert(@source, external_id: "a1", title: "Disk full")
    matched.update!(matched_policy_rule: rule, routing_state: Alert::ROUTING_ROUTED)
    create_alert(@source, external_id: "a2", title: "Container crash")

    get settings_alerts_url(source_id: @source.id, rule_id: rule.id), headers: inertia_headers

    assert_response :success
    alerts = inertia_props["alerts"]
    assert_equal [ matched.id ], alerts.map { |a| a["id"] }
    assert_equal 1, alerts.first["matchedRulePriority"]
    assert_equal @source.id, alerts.first["matchedRuleSourceId"]
    assert_equal [ rule.id ], inertia_props["ruleOptions"].map { |r| r["id"] }
  end

  test "without a source filter rule options span all policies with scope labels" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "NF routing", scoped_to: @source)
    policy.policy_rules.create!(priority: 1,
                                conditions: [ { field: "event", operator: PolicyRule::OPERATOR_CONTAINS, value: "crash" } ],
                                outcome: { "action" => AlertIngestService::ACTION_DROP })
    fallback = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Default routing")
    fallback.policy_rules.create!(priority: 1, conditions: [],
                                  outcome: { "action" => AlertIngestService::ACTION_DROP })

    get settings_alerts_url, headers: inertia_headers

    assert_response :success
    labels = inertia_props["ruleOptions"].map { |r| r["label"] }
    assert_includes labels, "Northflank · rule 1 · event contains crash"
    assert_includes labels, "rule 1 · always matches"
  end

  test "does not leak alerts from other workspaces" do
    other_workspace = workspaces(:slack_workspace_two)
    foreign_source = other_workspace.alert_sources.create!(name: "Foreign", provider: AlertSource::PROVIDER_GENERIC)
    create_alert(foreign_source, external_id: "f1", title: "Foreign alert", workspace: other_workspace)

    get settings_alerts_url, headers: inertia_headers

    assert_response :success
    assert_empty inertia_props["alerts"]
  end

  private

  def create_alert(source, external_id:, title:, workspace: @workspace, last_seen_at: Time.current,
                   routing_state: Alert::ROUTING_PENDING)
    Alert.create!(
      workspace: workspace,
      alert_source: source,
      external_id: external_id,
      fingerprint: Digest::SHA256.hexdigest(external_id),
      fields: { "title" => title },
      status: Alert::STATUS_FIRING,
      routing_state: routing_state,
      received_at: last_seen_at,
      last_seen_at: last_seen_at
    )
  end

  def inertia_props
    JSON.parse(response.body)["props"]
  end

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
