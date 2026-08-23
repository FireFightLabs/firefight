require "test_helper"

class McpRunbookToolsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    _, @personal_token = create_service_key(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Personal"
    )

    @failover = @workspace.runbooks.create!(name: "Database failover", summary: "Promote the replica")
    @failover.runbook_steps.create!(title: "Pause writes", instruction: "Stop the writer", position: 1)
    @failover.runbook_steps.create!(title: "Promote replica", instruction: "Run failover", position: 2)

    @rollback = @workspace.runbooks.create!(name: "Deploy rollback", summary: "Revert the release")
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

  test "tools/list includes the runbook tools as read-only" do
    tools = rpc("tools/list").dig("result", "tools")
    names = tools.map { |t| t["name"] }

    assert_includes names, Mcp::Tools::SEARCH_RUNBOOKS
    assert_includes names, Mcp::Tools::GET_RUNBOOK
    assert tools.select { |t| [ Mcp::Tools::SEARCH_RUNBOOKS, Mcp::Tools::GET_RUNBOOK ].include?(t["name"]) }
      .all? { |t| t.dig("annotations", "readOnlyHint") }
  end

  test "search_runbooks returns active runbooks ordered with step counts" do
    content, is_error = call_tool(Mcp::Tools::SEARCH_RUNBOOKS)

    assert_not is_error
    slugs = content["runbooks"].map { |r| r["slug"] }
    assert_includes slugs, @failover.slug
    assert_includes slugs, @rollback.slug
    failover = content["runbooks"].find { |r| r["slug"] == @failover.slug }
    assert_equal 2, failover["steps_count"]
    assert_not content["truncated"]
  end

  test "search_runbooks respects the query filter" do
    content, is_error = call_tool(Mcp::Tools::SEARCH_RUNBOOKS, { query: "failover" })

    assert_not is_error
    assert_equal [ @failover.slug ], content["runbooks"].map { |r| r["slug"] }
  end

  test "get_runbook returns full content and ordered steps" do
    @failover.update!(content: "Full failover procedure", external_url: "https://wiki/failover")

    content, is_error = call_tool(Mcp::Tools::GET_RUNBOOK, { slug: @failover.slug })

    assert_not is_error
    assert_equal @failover.slug, content["slug"]
    assert_equal "Full failover procedure", content["content"]
    assert_equal "https://wiki/failover", content["external_url"]
    assert_equal [ "Pause writes", "Promote replica" ], content["steps"].map { |s| s["title"] }
    assert_equal [ 1, 2 ], content["steps"].map { |s| s["position"] }
  end

  test "get_runbook does not find a soft-deleted runbook" do
    @rollback.update!(deleted_at: Time.current)

    _, is_error = call_tool(Mcp::Tools::GET_RUNBOOK, { slug: @rollback.slug })

    assert is_error
  end

  test "search_runbooks excludes soft-deleted runbooks" do
    @rollback.update!(deleted_at: Time.current)

    content, _ = call_tool(Mcp::Tools::SEARCH_RUNBOOKS)

    assert_not_includes content["runbooks"].map { |r| r["slug"] }, @rollback.slug
  end

  test "a slug that resolves to nothing is an error, never a silent duplicate" do
    result = rpc("tools/call", { name: Mcp::Tools::UPSERT_RUNBOOK,
                                 arguments: { slug: "deleted-since-you-read-it", name: "Ghost" } }).fetch("result")

    assert result["isError"]
    assert_includes result["content"].first["text"], "Not found in this workspace."
    assert_not @workspace.runbooks.exists?(name: "Ghost")
  end

  test "upsert_runbook resolves a severity slug to the id conditions match on" do
    critical = @workspace.incident_severities.active.find_by!(slug: "critical")

    content, is_error = call_tool(Mcp::Tools::UPSERT_RUNBOOK, {
      name: "Slug conditions",
      conditions: [ { condition_field: "severity", operator: "one_of", values: [ "critical" ] } ]
    })
    assert_not is_error

    runbook = @workspace.runbooks.find_by!(slug: content["slug"])
    assert_equal [ critical.id ], runbook.incident_conditions.first.values
  end

  test "upsert_runbook still accepts ids, so a read-modify-write round trips" do
    major = @workspace.incident_severities.active.find_by!(slug: "major")

    content, is_error = call_tool(Mcp::Tools::UPSERT_RUNBOOK, {
      name: "Id conditions",
      conditions: [ { condition_field: "severity", operator: "one_of", values: [ major.id ] } ]
    })
    assert_not is_error

    runbook = @workspace.runbooks.find_by!(slug: content["slug"])
    assert_equal [ major.id ], runbook.incident_conditions.first.values
  end

  test "upsert_runbook resolves a custom field slug and a catalog entry slug into the ids conditions match on" do
    definition = incident_field_definitions(:affected_services_ws1)
    auth_service = catalog_entries(:auth_service)

    content, is_error = call_tool(Mcp::Tools::UPSERT_RUNBOOK, {
      name: "Catalog conditions",
      conditions: [ { condition_field: "custom_field", custom_field: definition.slug,
                      operator: "one_of", values: [ auth_service.slug ] } ]
    })
    assert_not is_error

    condition = @workspace.runbooks.find_by!(slug: content["slug"]).incident_conditions.first
    assert_equal definition, condition.incident_field_definition
    assert_equal [ auth_service.id ], condition.values
  end

  test "upsert_runbook resolves an option label for a fixed list custom field" do
    definition = incident_field_definitions(:customer_tier_ws1)
    enterprise = incident_field_options(:customer_tier_enterprise)

    content, is_error = call_tool(Mcp::Tools::UPSERT_RUNBOOK, {
      name: "Option conditions",
      conditions: [ { condition_field: "custom_field", custom_field: definition.slug,
                      operator: "one_of", values: [ enterprise.label ] } ]
    })
    assert_not is_error

    condition = @workspace.runbooks.find_by!(slug: content["slug"]).incident_conditions.first
    assert_equal definition, condition.incident_field_definition
    assert_equal [ enterprise.id ], condition.values
  end

  test "upsert_runbook still accepts a custom field condition given entirely as ids" do
    definition = incident_field_definitions(:customer_tier_ws1)
    pro = incident_field_options(:customer_tier_pro)

    content, is_error = call_tool(Mcp::Tools::UPSERT_RUNBOOK, {
      name: "Id custom conditions",
      conditions: [ { condition_field: "custom_field", incident_field_definition_id: definition.id,
                      operator: "one_of", values: [ pro.id ] } ]
    })
    assert_not is_error

    condition = @workspace.runbooks.find_by!(slug: content["slug"]).incident_conditions.first
    assert_equal definition, condition.incident_field_definition
    assert_equal [ pro.id ], condition.values
  end

  test "upsert_runbook refuses a custom field condition naming no field" do
    _, is_error = call_tool(Mcp::Tools::UPSERT_RUNBOOK, {
      name: "Unknown field",
      conditions: [ { condition_field: "custom_field", custom_field: "not_a_field",
                      operator: "one_of", values: [ "Enterprise" ] } ]
    })

    assert is_error
    assert_not @workspace.runbooks.exists?(name: "Unknown field")
  end

  test "upsert_runbook refuses a custom field value matching none of what the field offers" do
    definition = incident_field_definitions(:customer_tier_ws1)

    _, is_error = call_tool(Mcp::Tools::UPSERT_RUNBOOK, {
      name: "Unknown option",
      conditions: [ { condition_field: "custom_field", custom_field: definition.slug,
                      operator: "one_of", values: [ "Platinum" ] } ]
    })

    assert is_error
    assert_not @workspace.runbooks.exists?(name: "Unknown option")
  end

  test "upsert_runbook refuses a value matching no severity rather than storing a dead condition" do
    _, is_error = call_tool(Mcp::Tools::UPSERT_RUNBOOK, {
      name: "Bad conditions",
      conditions: [ { condition_field: "severity", operator: "one_of", values: [ "sev1" ] } ]
    })

    assert is_error
    assert_not @workspace.runbooks.exists?(name: "Bad conditions")
  end

  test "a service key without runbooks:read is denied" do
    _, incidents_token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Incidents only",
      permissions: { ApiKey::RESOURCE_INCIDENTS => [ ApiKey::ACTION_READ ] }
    )

    result, is_error = call_tool(Mcp::Tools::SEARCH_RUNBOOKS, {}, token: incidents_token)
    assert is_error
    assert_empty result

    _, is_error = call_tool(Mcp::Tools::GET_RUNBOOK, { slug: @failover.slug }, token: incidents_token)
    assert is_error
  end

  test "attach_runbook posts the runbook into the incident and is idempotent" do
    incident = Incident.create!(
      workspace: @workspace, declared_by: @membership,
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: @workspace.incident_severities.active.find_by!(slug: "critical"),
      name: "Test incident", is_private: false, channel_id: "C_ATTACH", source: Incident::SOURCE_SLACK
    )
    stub_post_message

    content, is_error = call_tool(Mcp::Tools::ATTACH_RUNBOOK, {
      incident: incident.identifier, runbook: @failover.slug
    })
    assert_not is_error
    assert_equal @failover.slug, content["runbook"]
    assert content["newly_attached"]

    content, is_error = call_tool(Mcp::Tools::ATTACH_RUNBOOK, {
      incident: incident.identifier, runbook: @failover.slug
    })
    assert_not is_error
    assert_not content["newly_attached"]
    assert_equal 1, incident.incident_runbooks.count
  end

  test "attach_runbook refuses an unknown slug and names what is available" do
    incident = Incident.create!(
      workspace: @workspace, declared_by: @membership,
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: @workspace.incident_severities.active.find_by!(slug: "critical"),
      name: "Test incident", is_private: false, channel_id: "C_ATTACH2", source: Incident::SOURCE_SLACK
    )

    _, is_error = call_tool(Mcp::Tools::ATTACH_RUNBOOK, {
      incident: incident.identifier, runbook: "not_a_runbook"
    })

    assert is_error
    assert_equal 0, incident.incident_runbooks.count
  end
end
