require "test_helper"

# Managing agents, service keys, alert sources and webhooks from Claude Code.
# The credential tools authorize as admin-only resources, so a person reaches
# them and a machine never can, however it was granted.
class McpCredentialToolsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @membership = workspace_memberships(:alice_workspace_one)

    _, @admin_token = ApiKey.create_with_token!(
      workspace: @workspace, created_by: @membership, on_behalf_of: @membership, name: "Admin"
    )
  end

  # The rule the gateway exists to keep: a machine cannot mint another machine,
  # whatever anyone tries to grant it.
  test "an agent cannot reach the credential tools even when granted everything grantable" do
    _, token = create_agent(
      workspace: @workspace, created_by: @membership, name: "Ambitious", slug: "ambitious",
      permissions: Ability::Action::GRANTABLE_RESOURCES.index_with { %w[read create update delete] }
    )

    [ Mcp::Tools::UPSERT_AGENT, Mcp::Tools::LIST_AGENTS,
      Mcp::Tools::UPSERT_API_KEY, Mcp::Tools::LIST_API_KEYS ].each do |name|
      _, is_error = call_tool(name, { name: "Nope", slug: "nope" }, token: token)
      assert is_error, "#{name} should be out of reach for an agent"
    end

    assert_nil @workspace.agents.find_by(slug: "nope")
  end

  test "creating an agent hands back its token once and nothing it can do yet" do
    content, is_error = call_tool(Mcp::Tools::UPSERT_AGENT, {
      name: "Support agent", description: "Triages tickets"
    })

    assert_not is_error, content.inspect
    agent = @workspace.agents.find_by!(slug: "support_agent")
    assert_match(/\Aff_/, content["token"])
    assert_equal 1, content["live_tokens"]
    assert_equal 0, content["granted_abilities"]
    assert_equal @membership, agent.api_keys.sole.created_by
  end

  test "the token authenticates as the agent, not as whoever minted it" do
    content, = call_tool(Mcp::Tools::UPSERT_AGENT, { name: "Support agent" })
    agent = @workspace.agents.find_by!(slug: "support_agent")

    assert_equal agent, ApiKey.authenticate(content["token"]).principal
  end

  test "rotating leaves the old token working and a listing names both" do
    first, = call_tool(Mcp::Tools::UPSERT_AGENT, { name: "Rotator" })
    second, is_error = call_tool(Mcp::Tools::ROTATE_AGENT_TOKEN, { slug: "rotator" })

    assert_not is_error, second.inspect
    assert_not_equal first["token"], second["token"]
    assert_not_nil ApiKey.authenticate(first["token"])
    assert_equal 2, second["live_tokens"]

    listed, = call_tool(Mcp::Tools::LIST_AGENTS)
    prefixes = listed["agents"].find { |a| a["slug"] == "rotator" }["tokens"].map { |t| t["prefix"] }
    assert_equal 2, prefixes.size
  end

  test "revoking one token by prefix leaves the agent running on the other" do
    first, = call_tool(Mcp::Tools::UPSERT_AGENT, { name: "Rotator" })
    call_tool(Mcp::Tools::ROTATE_AGENT_TOKEN, { slug: "rotator" })
    prefix = ApiKey.authenticate(first["token"]).token_prefix

    content, is_error = call_tool(Mcp::Tools::REVOKE_AGENT_TOKEN, { slug: "rotator", token_prefix: prefix })

    assert_not is_error, content.inspect
    assert_nil ApiKey.authenticate(first["token"])
    assert_equal 1, content["live_tokens"]
  end

  test "deleting an agent takes its tokens with it" do
    content, = call_tool(Mcp::Tools::UPSERT_AGENT, { name: "Doomed" })

    _, is_error = call_tool(Mcp::Tools::DELETE_AGENT, { slug: "doomed" })

    assert_not is_error
    assert_nil ApiKey.authenticate(content["token"])
    assert_nil @workspace.agents.find_by(slug: "doomed")
  end

  test "a service key is minted with the permissions it was asked for" do
    content, is_error = call_tool(Mcp::Tools::UPSERT_API_KEY, {
      name: "Datadog", permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read create] }
    })

    assert_not is_error, content.inspect
    assert_match(/\Aff_/, content["token"])
    key = ApiKey.authenticate(content["token"])
    assert_equal({ "incidents" => %w[read create] }, key.granted_permissions)
    assert key.service?
  end

  test "sending permissions replaces the set rather than adding to it" do
    content, = call_tool(Mcp::Tools::UPSERT_API_KEY, {
      name: "Narrowing", permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read create update] }
    })

    call_tool(Mcp::Tools::UPSERT_API_KEY, {
      prefix: content["prefix"], permissions: { Ability::Action::RESOURCE_INCIDENTS => %w[read] }
    })

    key = @workspace.api_keys.find_by!(token_prefix: content["prefix"])
    assert_equal({ "incidents" => %w[read] }, key.granted_permissions)
  end

  test "a listing never carries a token" do
    call_tool(Mcp::Tools::UPSERT_API_KEY, { name: "Datadog" })

    content, = call_tool(Mcp::Tools::LIST_API_KEYS)

    assert content["api_keys"].any?
    assert content["api_keys"].none? { |key| key.key?("token") }
  end

  test "a personal token is not listed among the workspace's service keys" do
    content, = call_tool(Mcp::Tools::LIST_API_KEYS)

    assert content["api_keys"].none? { |key| key["name"] == "Admin" }
  end

  test "an alert source is created and reachable at its endpoint path" do
    content, is_error = call_tool(Mcp::Tools::UPSERT_ALERT_SOURCE, { name: "Datadog monitors" })

    assert_not is_error, content.inspect
    source = @workspace.alert_sources.find_by!(name: "Datadog monitors")
    assert_equal source.endpoint_path, content["slug"]
    assert_equal AlertSource::PROVIDER_GENERIC, content["provider"]
  end

  test "an alert source can be disabled without losing its endpoint" do
    created, = call_tool(Mcp::Tools::UPSERT_ALERT_SOURCE, { name: "Noisy" })

    content, is_error = call_tool(Mcp::Tools::UPSERT_ALERT_SOURCE, {
      slug: created["slug"], enabled: false
    })

    assert_not is_error, content.inspect
    assert_not content["enabled"]
    assert @workspace.alert_sources.exists?(endpoint_path: created["slug"])
  end

  test "a webhook is created with the events it subscribes to" do
    events = [ Webhook::SUBSCRIBABLE_EVENTS.first ]

    content, is_error = call_tool(Mcp::Tools::UPSERT_WEBHOOK, {
      name: "Ops relay", url: "https://example.com/hooks/firefight", subscribed_events: events
    })

    assert_not is_error, content.inspect
    assert_equal events, content["subscribed_events"]
    assert @workspace.webhooks.exists?(name: "Ops relay")
  end

  test "a webhook signing secret is never returned by a write" do
    content, = call_tool(Mcp::Tools::UPSERT_WEBHOOK, {
      name: "Ops relay", url: "https://example.com/hooks/firefight"
    })

    assert_not content.key?("signing_secret")
  end

  test "a key granted alerts can manage alert sources but not agents" do
    _, token = create_service_key(
      workspace: @workspace, created_by: @membership, name: "Alerting",
      permissions: { Ability::Action::RESOURCE_ALERTS => %w[read create update delete] }
    )

    _, is_error = call_tool(Mcp::Tools::UPSERT_ALERT_SOURCE, { name: "From a key" }, token: token)
    assert_not is_error

    _, is_error = call_tool(Mcp::Tools::UPSERT_AGENT, { name: "Nope" }, token: token)
    assert is_error
  end

  private

  def rpc(method, params = {}, id: 1, token: @admin_token)
    post mcp_path,
         params: { jsonrpc: "2.0", id: id, method: method, params: params }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
    JSON.parse(response.body)
  end

  def call_tool(name, arguments = {}, token: @admin_token)
    result = rpc("tools/call", { name: name, arguments: arguments }, token: token).fetch("result")
    [ result["structuredContent"] || {}, result["isError"], result.dig("content", 0, "text") ]
  end
end
