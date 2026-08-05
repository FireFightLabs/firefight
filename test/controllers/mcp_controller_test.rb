require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents, :incident_events,
           :incident_roles, :incident_role_assignments, :catalog_types,
           :catalog_attribute_definitions, :catalog_entries, :catalog_entry_relationships

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    _, @personal_token = create_service_key(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Personal"
    )
  end

  def rpc(method, params = {}, id: 1, token: @personal_token)
    post mcp_path,
         params: { jsonrpc: "2.0", id: id, method: method, params: params }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
    JSON.parse(response.body)
  end

  def call_tool(name, arguments = {}, token: @personal_token)
    body = rpc("tools/call", { name: name, arguments: arguments }, token: token)
    result = body.fetch("result")
    [ result["structuredContent"] || {}, result["isError"] ]
  end

  test "requires a bearer token and advertises how to authenticate" do
    post mcp_path, params: { jsonrpc: "2.0", id: 1, method: "ping" }.to_json,
         headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], "Firefight MCP"
  end

  test "only POST is allowed" do
    get "/mcp", headers: { "Authorization" => "Bearer #{@personal_token}" }
    assert_response :method_not_allowed

    delete "/mcp", headers: { "Authorization" => "Bearer #{@personal_token}" }
    assert_response :method_not_allowed
  end

  test "initialize negotiates and tools/list exposes the read-only surface" do
    body = rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "0" } })
    assert_equal McpController::SERVER_NAME, body.dig("result", "serverInfo", "name")

    body = rpc("tools/list")
    tools = body.dig("result", "tools")
    assert_equal [ Mcp::Tools::EVALUATE_ROUTING, Mcp::Tools::GET_INCIDENT, Mcp::Tools::GET_RUNBOOK,
                   Mcp::Tools::SEARCH_ALERTS, Mcp::Tools::SEARCH_CATALOG, Mcp::Tools::SEARCH_INCIDENTS,
                   Mcp::Tools::SEARCH_RUNBOOKS, Mcp::Tools::UPSERT_CATALOG_ENTRY,
                   Mcp::Tools::DELETE_CATALOG_ENTRY, Mcp::Tools::UPSERT_ROUTING_RULE,
                   Mcp::Tools::DELETE_ROUTING_RULE, Mcp::Tools::UPDATE_ROUTING_CONFIG,
                   Mcp::Tools::UPSERT_RUNBOOK, Mcp::Tools::ASSIGN_INCIDENT_ROLE,
                   Mcp::Tools::SEARCH_APPROVALS,
                   Mcp::Tools::APPROVE_APPROVAL, Mcp::Tools::DENY_APPROVAL,
                   Mcp::Tools::GET_FORM, Mcp::Tools::UPSERT_CUSTOM_FIELD,
                   Mcp::Tools::UPSERT_FORM_FIELD ].sort,
                 tools.map { |t| t["name"] }.sort

    read_tools, write_tools = tools.partition { |t| t["name"].start_with?("search", "get", "evaluate") }
    assert read_tools.all? { |t| t.dig("annotations", "readOnlyHint") }
    assert write_tools.all? { |t| t.dig("annotations", "readOnlyHint") == false }
  end

  test "search_incidents returns workspace incidents with filters and caps" do
    content, is_error = call_tool(Mcp::Tools::SEARCH_INCIDENTS, { limit: 2 })

    assert_not is_error
    assert_equal 2, content["incidents"].size
    assert content["truncated"]
    assert content["incidents"].first.key?("identifier")

    content, _ = call_tool(Mcp::Tools::SEARCH_INCIDENTS, { query: incidents(:active_critical_ws1).identifier })
    assert_equal [ incidents(:active_critical_ws1).identifier ], content["incidents"].map { |i| i["identifier"] }
  end

  test "get_incident resolves by identifier with timeline" do
    incident = incidents(:active_critical_ws1)

    content, is_error = call_tool(Mcp::Tools::GET_INCIDENT, { incident: incident.identifier })

    assert_not is_error
    assert_equal incident.identifier, content["identifier"]
    assert content["timeline"].is_a?(Array)
  end

  test "cross-workspace incidents are invisible" do
    foreign = Incident.where(workspace: workspaces(:slack_workspace_two)).first

    _, is_error = call_tool(Mcp::Tools::GET_INCIDENT, { incident: foreign.id })

    assert is_error
  end

  test "search_alerts reflects routing state and matched rule" do
    source = @workspace.alert_sources.create!(name: "Grafana", provider: AlertSource::PROVIDER_GENERIC)
    source.alerts.create!(workspace: @workspace, external_id: "a1", fingerprint: "f1",
                          fields: { "title" => "Disk full" }, routing_state: Alert::ROUTING_UNMATCHED,
                          received_at: Time.current, last_seen_at: Time.current)

    content, is_error = call_tool(Mcp::Tools::SEARCH_ALERTS, { routing_state: Alert::ROUTING_UNMATCHED })

    assert_not is_error
    assert_equal [ "Disk full" ], content["alerts"].map { |a| a["title"] }
    assert_equal "Grafana", content["alerts"].first["source"]
  end

  test "search_catalog returns entries with relationships" do
    content, is_error = call_tool(Mcp::Tools::SEARCH_CATALOG, { slug: catalog_entries(:auth_service).slug })

    assert_not is_error
    entry = content["entries"].first
    assert_equal catalog_entries(:auth_service).slug, entry["slug"]
    assert entry["relationships"].any? { |r| r["target_slug"] == catalog_entries(:platform_team).slug }
  end

  test "evaluate_routing dry-runs the workspace policy with a trace" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "checkout" ] } ],
      outcome: { "action" => AlertIngestService::ACTION_AUTO_CREATE }
    )

    content, is_error = call_tool(Mcp::Tools::EVALUATE_ROUTING, { fields: { service: "checkout" } })

    assert_not is_error
    assert content["matched"]
    assert_equal 1, content["matched_rule_priority"]
    assert_equal AlertIngestService::ACTION_AUTO_CREATE, content.dig("outcome", "action")
    assert content["trace"].is_a?(Array)
  end

  test "initialize advertises product docs and tool descriptions link to them" do
    body = rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "0" } })
    assert_includes body.dig("result", "instructions"), Mcp::Docs::INDEX

    body = rpc("tools/list")
    body.dig("result", "tools").each do |tool|
      assert_includes tool["description"], Mcp::Docs::BASE, "#{tool["name"]} description lacks a docs link"
    end
  end

  test "evaluate_routing points at routing docs only when nothing matches" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "checkout" ] } ],
      outcome: { "action" => AlertIngestService::ACTION_AUTO_CREATE }
    )

    content, is_error = call_tool(Mcp::Tools::EVALUATE_ROUTING, { fields: { service: "search" } })
    assert_not is_error
    assert_not content["matched"]
    assert_equal Mcp::Docs::ROUTING_RULES, content["docs_url"]

    content, _ = call_tool(Mcp::Tools::EVALUATE_ROUTING, { fields: { service: "checkout" } })
    assert content["matched"]
    assert_nil content["docs_url"]
  end

  test "permission and missing-policy errors link to the relevant docs" do
    _, alerts_token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Alerts only",
      permissions: { ApiKey::RESOURCE_ALERTS => [ ApiKey::ACTION_READ ] }
    )
    body = rpc("tools/call", { name: Mcp::Tools::SEARCH_INCIDENTS, arguments: {} }, token: alerts_token)
    assert_includes body.dig("result", "content").first["text"], Mcp::Docs::MCP_SERVER

    body = rpc("tools/call", { name: Mcp::Tools::EVALUATE_ROUTING, arguments: { fields: { service: "x" } } })
    assert_includes body.dig("result", "content").first["text"], Mcp::Docs::ROUTING_RULES
  end

  test "evaluate_routing resolves outcome target ids to names" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [],
      outcome: {
        "action" => AlertIngestService::ACTION_AUTO_CREATE,
        "severity_id" => incident_severities(:critical_ws1).id,
        "invite" => [
          { "type" => PolicyRule::AlertRoutingOutcome::TARGET_MEMBER, "member_id" => @membership.id },
          { "type" => PolicyRule::AlertRoutingOutcome::TARGET_TEAM, "entry_id" => catalog_entries(:platform_team).id }
        ]
      }
    )

    content, is_error = call_tool(Mcp::Tools::EVALUATE_ROUTING, { fields: { service: "checkout" } })

    assert_not is_error
    assert_equal "Critical", content.dig("outcome", "severity_name")
    invites = content.dig("outcome", "invite")
    assert_equal "Alice Smith", invites.first["member_name"]
    assert_equal "Platform Team", invites.second["entry_name"]
    assert_equal "platform_team", invites.second["entry_slug"]
  end

  test "search_catalog resolves member attribute ids to names" do
    catalog_types(:team_ws1).catalog_attribute_definitions.create!(
      slug: "manager", name: "Manager",
      attribute_type: CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBER, position: 5
    )
    entry = catalog_entries(:platform_team)
    entry.update!(attributes: entry.attributes.merge("manager" => @membership.id))

    content, is_error = call_tool(Mcp::Tools::SEARCH_CATALOG, { slug: entry.slug })

    assert_not is_error
    manager = content["entries"].first.dig("attributes", "manager")
    assert_equal @membership.id, manager["id"]
    assert_equal "Alice Smith", manager["name"]
  end

  test "service keys are scoped per tool resource" do
    _, alerts_token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Alerts only",
      permissions: { ApiKey::RESOURCE_ALERTS => [ ApiKey::ACTION_READ ] }
    )

    _, is_error = call_tool(Mcp::Tools::SEARCH_ALERTS, {}, token: alerts_token)
    assert_not is_error

    result, is_error = call_tool(Mcp::Tools::SEARCH_INCIDENTS, {}, token: alerts_token)
    assert is_error
    assert_empty result
  end

  test "admin personal tokens can write config: catalog upsert, routing rule, runbook" do
    content, is_error = call_tool(Mcp::Tools::UPSERT_CATALOG_ENTRY,
                                  { type: "service", name: "Checkout", attributes: { description: "Payments front" } })
    assert_not is_error
    assert_equal "Checkout", content["name"]
    entry = @workspace.catalog_entries.find_by!(slug: content["slug"])
    assert_equal "Payments front", entry.attributes["description"]

    content, is_error = call_tool(Mcp::Tools::UPSERT_CATALOG_ENTRY,
                                  { type: "service", slug: content["slug"], attributes: { description: "Owns checkout" } })
    assert_not is_error
    assert_equal "Owns checkout", entry.reload.attributes["description"]

    content, is_error = call_tool(Mcp::Tools::UPSERT_ROUTING_RULE, {
      conditions: [ { field: "service", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "checkout" ] } ],
      outcome: { action: AlertIngestService::ACTION_AUTO_CREATE }
    })
    assert_not is_error
    assert_equal 1, content["priority"]

    evaluation, _ = call_tool(Mcp::Tools::EVALUATE_ROUTING, { fields: { service: "checkout" } })
    assert evaluation["matched"]

    content, is_error = call_tool(Mcp::Tools::UPSERT_RUNBOOK, {
      name: "DB failover", summary: "Fail the database over",
      steps: [ { title: "Check replica", instruction: "Confirm replica lag" } ],
      conditions: [ { condition_field: IncidentCondition::FIELD_SEVERITY, operator: IncidentCondition::OPERATOR_ONE_OF,
                      values: [ incident_severities(:critical_ws1).id ] } ]
    })
    assert_not is_error
    runbook = @workspace.runbooks.find_by!(slug: content["slug"])
    assert_equal 1, runbook.runbook_steps.count
    assert_equal 1, runbook.incident_conditions.count

    invocation = Ability::Invocation.find_by!(action_key: "runbooks.create")
    assert_equal Ability::Invocation::OUTCOME_SUCCESS, invocation.outcome
  end

  test "member personal tokens cannot write config" do
    bob = workspace_memberships(:bob_workspace_one)
    _, bob_token = create_service_key(
      workspace: @workspace, created_by: bob, on_behalf_of: bob, name: "Bob's token"
    )

    result, is_error = call_tool(Mcp::Tools::UPSERT_CATALOG_ENTRY,
                                 { type: "service", name: "Nope" }, token: bob_token)

    assert is_error
    assert_empty result
  end

  test "routing config and rule deletion round-trip" do
    call_tool(Mcp::Tools::UPSERT_ROUTING_RULE, {
      conditions: [], outcome: { action: AlertIngestService::ACTION_DROP }
    })

    content, is_error = call_tool(Mcp::Tools::UPDATE_ROUTING_CONFIG,
                                  { grouping_window_minutes: 30, content_match_fields: [ "service", "title" ] })
    assert_not is_error
    assert_equal 30, content["grouping_window_minutes"]
    assert_equal [ "service", "title" ], content["content_match_fields"]

    content, is_error = call_tool(Mcp::Tools::DELETE_ROUTING_RULE, { priority: 1 })
    assert_not is_error
    assert content["deleted"]
    assert_equal 0, @workspace.alert_routing_policy.policy_rules.count
  end

  test "write tools park behind approval policies and execute on the approved retry" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_APPROVALS, name: "Approvals")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [ { field: "risk_level", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "write" ] } ],
      outcome: { "require" => { "role" => WorkspaceMembership.roles[:admin], "count" => 1 } }
    )

    body = rpc("tools/call", { name: Mcp::Tools::UPSERT_CATALOG_ENTRY,
                               arguments: { type: "service", name: "Gated" } })
    result = body.fetch("result")
    assert result["isError"]
    error_text = result["content"].first["text"]
    approval = @workspace.ability_approvals.pending.find_by!(action_key: "catalog.create")
    assert_includes error_text, approval.id

    approval.approve!(by: workspace_memberships(:bob_workspace_one).tap { |m| m.update!(role: :admin) })

    content, is_error = call_tool(Mcp::Tools::UPSERT_CATALOG_ENTRY,
                                  { type: "service", name: "Gated", approval_id: approval.id })
    assert_not is_error
    assert @workspace.catalog_entries.exists?(name: "Gated")
  end

  test "approvals resolve over MCP for humans, never for service keys" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_APPROVALS, name: "Approvals")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [ { field: "risk_level", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "write" ] } ],
      outcome: { "require" => { "role" => WorkspaceMembership.roles[:admin], "count" => 1 } }
    )
    call_tool(Mcp::Tools::UPSERT_CATALOG_ENTRY, { type: "service", name: "Gated" })
    approval = @workspace.ability_approvals.pending.find_by!(action_key: "catalog.create")

    content, is_error = call_tool(Mcp::Tools::SEARCH_APPROVALS, { status: "pending" })
    assert_not is_error
    assert_equal [ approval.id ], content["approvals"].map { |a| a["id"] }

    _, service_token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Approver bot",
      permissions: { ApiKey::RESOURCE_APPROVALS => [ ApiKey::ACTION_READ, ApiKey::ACTION_UPDATE ] }
    )
    result, is_error = call_tool(Mcp::Tools::APPROVE_APPROVAL, { id: approval.id }, token: service_token)
    assert is_error
    assert approval.reload.pending?

    content, is_error = call_tool(Mcp::Tools::APPROVE_APPROVAL, { id: approval.id })
    assert_not is_error
    assert_equal Ability::Approval::STATUS_APPROVED, content["status"]

    content, is_error = call_tool(Mcp::Tools::UPSERT_CATALOG_ENTRY,
                                  { type: "service", name: "Gated", approval_id: approval.id })
    assert_not is_error
    assert @workspace.catalog_entries.exists?(name: "Gated")
  end

  test "connection tools are exposed outward, gateway-governed, and executed upstream" do
    integration = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "newrelic", name: "New Relic",
      settings: { "server_url" => "https://mcp.example/mcp" }
    )
    integration.integration_environments.create!(credentials: { authorization: "Bearer up" }.to_json)
    tool = integration.tools.create!(name: "logs.query", read_only: true, enabled: true,
                                     description: "Query logs", spec: { "tool_name" => "logs.query" })

    body = rpc("tools/list")
    names = body.dig("result", "tools").map { |t| t["name"] }
    assert_includes names, "new_relic_logs_query"

    # A service key holds only what it was granted, so it cannot reach a
    # newly enabled tool without one.
    _, service_token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Scoped bot",
      permissions: { ApiKey::RESOURCE_ALERTS => [ ApiKey::ACTION_READ ] }
    )
    result, is_error = call_tool("new_relic_logs_query", { query: "SELECT 1" }, token: service_token)
    assert is_error
    assert_empty result

    # The admin who enabled the capability can use it straight away.
    Integrations::McpClient.any_instance.expects(:call_tool)
      .with(name: "logs.query", arguments: { "query" => "SELECT 1" })
      .returns({ "content" => [ { "type" => "text", "text" => "42 rows" } ], "isError" => false })

    body = rpc("tools/call", { name: "new_relic_logs_query", arguments: { query: "SELECT 1" } })
    result = body.fetch("result")
    assert_not result["isError"]
    assert_equal "42 rows", result["content"].first["text"]

    integration.update!(disabled_at: Time.current)
    body = rpc("tools/call", { name: "new_relic_logs_query", arguments: { query: "SELECT 1" } })
    refute_nil body["error"], "the kill switch removes the tool from the registry entirely"
  end

  test "denied tool calls are recorded in the ability ledger" do
    key, alerts_token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Alerts only",
      permissions: { ApiKey::RESOURCE_ALERTS => [ ApiKey::ACTION_READ ] }
    )

    assert_difference "Ability::Invocation.count", 1 do
      call_tool(Mcp::Tools::SEARCH_INCIDENTS, {}, token: alerts_token)
    end

    invocation = Ability::Invocation.find_by!(principal_id: key.id, action_key: "incidents.read")
    assert_equal Ability::Invocation::DECISION_DENY, invocation.decision

    assert_no_difference "Ability::Invocation.count" do
      call_tool(Mcp::Tools::SEARCH_ALERTS, {}, token: alerts_token)
    end
  end
end
