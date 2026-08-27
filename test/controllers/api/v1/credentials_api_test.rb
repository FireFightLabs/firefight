require "test_helper"

# Agents and service keys over REST. Both authorize as admin-only resources, so
# an admin's personal token reaches them and no machine ever can.
class Api::V1::CredentialsApiTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)
    _, @admin_token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Admin"
    )
  end

  # The rule the gateway exists to keep, checked over REST as well as MCP.
  test "an agent granted everything grantable still cannot reach credentials" do
    _, token = create_agent(
      workspace: @workspace, created_by: @membership, name: "Ambitious", slug: "ambitious",
      permissions: Ability::Action::GRANTABLE_RESOURCES.index_with { %w[read create update delete] }
    )

    get api_v1_agents_url, headers: api_headers(token: token)
    assert_response :forbidden

    post api_v1_agents_url, params: { name: "Nope" }, headers: api_headers(token: token), as: :json
    assert_response :forbidden

    get api_v1_api_keys_url, headers: api_headers(token: token)
    assert_response :forbidden

    assert_nil @workspace.agents.find_by(slug: "nope")
  end

  test "creating an agent returns its token once and nothing it can do yet" do
    post api_v1_agents_url,
         params: { name: "Support agent", description: "Triages tickets" },
         headers: api_headers(token: @admin_token), as: :json

    assert_response :created
    assert_match(/\Aff_/, json_response["token"])
    assert_equal 0, json_response["granted_abilities"]
    assert_equal 1, json_response["tokens"].size

    agent = @workspace.agents.find_by!(slug: "support_agent")
    assert_equal agent, ApiKey.authenticate(json_response["token"]).principal
  end

  test "rotating leaves the old token working, and revoking one by prefix ends it" do
    post api_v1_agents_url, params: { name: "Rotator" }, headers: api_headers(token: @admin_token), as: :json
    first = json_response["token"]

    post rotate_api_v1_agent_url("rotator"), headers: api_headers(token: @admin_token), as: :json
    assert_response :created
    assert_not_equal first, json_response["token"]
    assert_not_nil ApiKey.authenticate(first)
    assert_equal 2, json_response["tokens"].size

    prefix = ApiKey.authenticate(first).token_prefix
    delete token_api_v1_agent_url("rotator", token_prefix: prefix), headers: api_headers(token: @admin_token)

    assert_response :no_content
    assert_nil ApiKey.authenticate(first)
  end

  test "a listing never carries a token" do
    post api_v1_agents_url, params: { name: "Support agent" }, headers: api_headers(token: @admin_token), as: :json

    get api_v1_agents_url, headers: api_headers(token: @admin_token)

    assert_response :success
    assert json_response["agents"].any?
    assert json_response["agents"].none? { |agent| agent.key?("token") }
  end

  test "deleting an agent takes its tokens with it" do
    post api_v1_agents_url, params: { name: "Doomed" }, headers: api_headers(token: @admin_token), as: :json
    token = json_response["token"]

    delete api_v1_agent_url("doomed"), headers: api_headers(token: @admin_token)

    assert_response :no_content
    assert_nil ApiKey.authenticate(token)
  end

  test "a service key is minted with the permissions it was asked for" do
    post api_v1_api_keys_url,
         params: { name: "Datadog", permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read create] } },
         headers: api_headers(token: @admin_token), as: :json

    assert_response :created
    key = ApiKey.authenticate(json_response["token"])
    assert_equal({ "incidents" => %w[read create] }, key.granted_permissions)
    assert key.service?
  end

  test "sending permissions replaces the set rather than adding to it" do
    post api_v1_api_keys_url,
         params: { name: "Narrowing", permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read create update] } },
         headers: api_headers(token: @admin_token), as: :json
    prefix = json_response["prefix"]

    patch api_v1_api_key_url(prefix),
          params: { permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read] } },
          headers: api_headers(token: @admin_token), as: :json

    assert_response :success
    assert_equal({ "incidents" => %w[read] }, @workspace.api_keys.find_by!(token_prefix: prefix).granted_permissions)
  end

  test "a personal token is not listed among the workspace's service keys" do
    get api_v1_api_keys_url, headers: api_headers(token: @admin_token)

    assert_response :success
    assert json_response["api_keys"].none? { |key| key["name"] == "Admin" }
    assert json_response["api_keys"].none? { |key| key.key?("token") }
  end

  test "another workspace's agent is not reachable" do
    create_agent(
      workspace: workspaces(:slack_workspace_two),
      created_by: workspace_memberships(:alice_workspace_two), slug: "elsewhere"
    )

    delete api_v1_agent_url("elsewhere"), headers: api_headers(token: @admin_token)

    assert_response :not_found
  end
end
