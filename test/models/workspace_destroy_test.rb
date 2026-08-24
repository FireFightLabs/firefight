require "test_helper"

class WorkspaceDestroyTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
  end

  test "destroy removes a fully loaded workspace without violating a foreign key" do
    incident = incidents(:active_critical_ws1)

    AlertGroup.create!(workspace: @workspace, incident: incident,
                       content_signature: AlertGroup.signature_for({ "service" => "api" }, [ "service" ]),
                       window_expires_at: 10.minutes.from_now)

    source = @workspace.alert_sources.create!(name: "Grafana", provider: AlertSource::PROVIDER_GENERIC)
    source.alerts.create!(workspace: @workspace, external_id: "a1", fingerprint: "f1",
                          fields: { "title" => "Disk full" }, incident: incident,
                          status: Alert::STATUS_FIRING,
                          received_at: Time.current, last_seen_at: Time.current)

    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog",
      settings: { "server_url" => "https://mcp.example/mcp" }
    )
    integration.integration_environments.create!(
      catalog_entry_id: catalog_entries(:production_env).id,
      credentials: { authorization: "Bearer x" }.to_json
    )
    tool = integration.tools.create!(name: "logs_query", read_only: true, enabled: true)
    Ability::Grant.create!(workspace: @workspace, principal: api_keys(:full_access_key), action: tool.ability_action)

    role = @workspace.ability_roles.create!(name: "Readers")
    role.role_actions.create!(action: tool.ability_action)

    inference = Inference.create!(workspace: @workspace, member: @membership, api_key: api_keys(:full_access_key),
                                  feature: "summary", provider: "openai", model: "gpt-4o-mini",
                                  status: Inference::STATUS_SUCCESS, inferable: incident)
    IncidentSummary.create!(workspace: @workspace, incident: incident, inference: inference,
                            content: "All quiet", summary_up_to_ts: "1234.5678",
                            generated_at: Time.current, model: "gpt-4o-mini")

    oauth_app = Doorkeeper::Application.create!(name: "Test agent", redirect_uri: "https://example.test/callback")
    Doorkeeper::AccessToken.create!(application: oauth_app, resource_owner_id: @membership.id, token: SecureRandom.hex(16))

    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(priority: 1, conditions: [],
                                outcome: { "action" => AlertIngestService::ACTION_DROP })

    workspace_id = @workspace.id
    membership_ids = @workspace.workspace_memberships.pluck(:id)

    @workspace.destroy!

    [ Incident, WorkspaceMembership, ApiKey, Alert, AlertGroup, AlertSource, Integration,
      CatalogType, CatalogEntry, Runbook, Webhook, Inference, IncidentSummary, Policy,
      IncidentStatus, IncidentFieldDefinition, IncidentForm, IdempotencyKey,
      Ability::Action, Ability::Grant, Ability::Role ].each do |model|
      assert_not model.where(workspace_id: workspace_id).exists?, "expected no #{model.table_name} rows"
    end
    assert_not Doorkeeper::AccessToken.where(resource_owner_id: membership_ids).exists?
  end

  test "destroying one workspace leaves the others and global actions untouched" do
    other = workspaces(:slack_workspace_two)
    other_incidents = other.incidents.count
    global_actions = Ability::Action.where(workspace_id: nil).count

    workspaces(:slack_workspace_one).destroy!

    assert_equal other_incidents, other.reload.incidents.count
    assert_equal global_actions, Ability::Action.where(workspace_id: nil).count
    assert User.exists?(users(:alice).id), "users survive their workspace"
  end
end
