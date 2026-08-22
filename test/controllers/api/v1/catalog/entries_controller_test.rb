require "test_helper"

class Api::V1::Catalog::EntriesControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :api_keys, :ability_actions, :ability_grants,
           :catalog_types, :catalog_attribute_definitions, :catalog_entries

  test "lists entries for a type, excluding deleted" do
    get api_v1_catalog_type_entries_path(slug: "team"), headers: api_headers
    assert_response :success

    names = json_response["entries"].map { |e| e["name"] }
    assert_includes names, "Platform Team"
    assert_not_includes names, "Old Team"
  end

  test "shows an entry with attributes" do
    get api_v1_catalog_entry_path(id: "cc000001-0000-0000-0000-000000000002"), headers: api_headers
    assert_response :success
    assert_equal "Auth Service", json_response["name"]
    assert_equal "Critical", json_response["attributes"]["tier"]
  end

  test "create inserts a new entry" do
    assert_difference -> { CatalogEntry.count }, 1 do
      post api_v1_catalog_type_entries_path(slug: "team"),
        params: { name: "Payments Team", attributes: { description: "Owns billing" } }.to_json,
        headers: api_headers
    end
    assert_response :created
    assert_equal "Payments Team", json_response["name"]
  end

  test "an approval policy parks api writes as 202 until approved, then the retry executes" do
    policy = workspaces(:slack_workspace_one).policies.create!(domain: Policy::DOMAIN_APPROVALS, name: "Approvals")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [ { field: "risk_level", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "write" ] } ],
      outcome: { "require" => { "role" => WorkspaceMembership.roles[:admin], "count" => 1 } }
    )

    assert_no_difference -> { CatalogEntry.count } do
      post api_v1_catalog_type_entries_path(slug: "team"),
        params: { name: "Gated Team", attributes: {} }.to_json,
        headers: api_headers
    end
    assert_response :accepted
    approval_id = json_response["approval_id"]
    assert approval_id.present?

    workspaces(:slack_workspace_one).ability_approvals.find(approval_id)
      .approve!(by: workspace_memberships(:alice_workspace_one))

    assert_difference -> { CatalogEntry.count }, 1 do
      post api_v1_catalog_type_entries_path(slug: "team"),
        params: { name: "Gated Team", attributes: {} }.to_json,
        headers: api_headers.merge("X-Approval-Id" => approval_id)
    end
    assert_response :created
  end

  test "api writes are ledgered write-ahead and finalized; denials are ledgered too" do
    post api_v1_catalog_type_entries_path(slug: "team"),
      params: { name: "Ledgered Team", attributes: {} }.to_json,
      headers: api_headers
    assert_response :created

    invocation = Ability::Invocation.find_by!(action_key: "catalog.create",
                                              principal_id: api_keys(:full_access_key).id)
    assert_equal Ability::Invocation::DECISION_ALLOW, invocation.decision
    assert_equal Ability::Invocation::OUTCOME_SUCCESS, invocation.outcome
    assert invocation.completed_at.present?

    post api_v1_catalog_type_entries_path(slug: "team"),
      params: { name: "Nope", attributes: {} }.to_json,
      headers: api_headers(token: "ff_test_read_only_token_12345678")
    assert_response :forbidden

    denial = Ability::Invocation.find_by!(action_key: "catalog.create",
                                          principal_id: api_keys(:read_only_key).id)
    assert_equal Ability::Invocation::DECISION_DENY, denial.decision
  end

  test "upsert by source + external_id updates instead of duplicating" do
    post api_v1_catalog_type_entries_path(slug: "team"),
      params: { name: "SRE", source: "backstage", external_id: "grp-sre", attributes: {} }.to_json,
      headers: api_headers
    assert_response :created
    created_id = json_response["id"]

    assert_no_difference -> { CatalogEntry.count } do
      post api_v1_catalog_type_entries_path(slug: "team"),
        params: { name: "SRE (renamed)", source: "backstage", external_id: "grp-sre", attributes: {} }.to_json,
        headers: api_headers
    end
    assert_response :ok
    assert_equal created_id, json_response["id"]
    assert_equal "SRE (renamed)", json_response["name"]
  end

  test "update changes an existing entry" do
    patch api_v1_catalog_entry_path(id: "cc000001-0000-0000-0000-000000000001"),
      params: { name: "Platform Eng" }.to_json,
      headers: api_headers
    assert_response :success
    assert_equal "Platform Eng", json_response["name"]
  end

  test "destroy soft-deletes the entry" do
    delete api_v1_catalog_entry_path(id: "cc000001-0000-0000-0000-000000000001"), headers: api_headers
    assert_response :no_content
    assert_not_nil CatalogEntry.find("cc000001-0000-0000-0000-000000000001").deleted_at
  end

  test "create sets a member attribute from the email that member signs in with" do
    define_team_lead_attribute

    post api_v1_catalog_type_entries_path(slug: "team"),
      params: { name: "Emailed Team", attributes: { team_lead: "alice@example.com" } }.to_json,
      headers: api_headers

    assert_response :created
    assert_equal workspace_memberships(:alice_workspace_one).id, json_response["attributes"]["team_lead"]
  end

  test "create refuses a member the workspace does not have, and adds nobody to it" do
    define_team_lead_attribute

    assert_no_difference [ -> { CatalogEntry.count }, -> { WorkspaceMembership.count } ] do
      post api_v1_catalog_type_entries_path(slug: "team"),
        params: { name: "Unresolved Team", attributes: { team_lead: "stranger@example.com" } }.to_json,
        headers: api_headers
    end

    assert_response :unprocessable_entity
    assert_equal "validation_error", json_response["error"]["type"]
    assert_includes json_response["error"]["message"], "stranger@example.com"
    assert_equal [ "base" ], json_response["error"]["errors"].map { |error| error["field"] }
  end

  test "write requires catalog:create permission" do
    post api_v1_catalog_type_entries_path(slug: "team"),
      params: { name: "Nope" }.to_json,
      headers: api_headers(token: "ff_test_read_only_token_12345678")
    assert_response :forbidden
  end

  private

  def define_team_lead_attribute
    catalog_types(:team_ws1).catalog_attribute_definitions.create!(
      slug: "team_lead",
      name: "Team Lead",
      attribute_type: CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBER,
      required: false,
      position: 20,
      config: {}
    )
  end
end
