require "test_helper"

# A general tool reaches a whole API, so whether one call is a change customers feel is told call by call by its
# provider's reader.
class Integrations::MitigationsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    cloudflare = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                 settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    @execute = cloudflare.tools.create!(name: "execute", description: "Call the API", enabled: true, read_only: false, params_schema: {})
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
    @row = northflank.integration_environments.create!(credentials: { token: "x" }.to_json)
    @api = northflank.tools.create!(name: "api_request", description: "API", enabled: true, read_only: false, params_schema: {})
  end

  test "a Cloudflare script that creates or changes a rule is one, and a read or a removal is not" do
    block = %(async () => cloudflare.request({ method: "POST", path: "/zones/z1/rulesets/r1/rules", body: { action: "block", expression: "ip.src eq 1.2.3.4" } }))
    limit = %(async () => cloudflare.request({ method: 'PUT', path: '/zones/z1/rate_limits/l1', body: {} }))
    read = %(async () => cloudflare.request({ method: "GET", path: "/zones/z1/rulesets" }))
    removal = %(async () => cloudflare.request({ method: "DELETE", path: "/zones/z1/firewall/access_rules/rules/a1" }))
    dns = %(async () => cloudflare.request({ method: "POST", path: "/zones/z1/dns_records", body: {} }))

    assert Integrations::Mitigations.call?(@execute, { "code" => block })
    assert Integrations::Mitigations.call?(@execute, { "code" => limit })
    assert_not Integrations::Mitigations.call?(@execute, { "code" => read })
    assert_not Integrations::Mitigations.call?(@execute, { "code" => removal })
    assert_not Integrations::Mitigations.call?(@execute, { "code" => dns })
  end

  test "a Northflank pause, a scale to none, or a scale below what the map last read is one, and a scale up is not" do
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web",
                                  name: "web", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current, details: { "instances" => 3 })

    assert Integrations::Mitigations.call?(@api, { "method" => "POST", "path" => "services/web/pause" })
    assert Integrations::Mitigations.call?(@api, { "method" => "POST", "path" => "services/worker/scale", "body" => { "instances" => 0 } })
    assert Integrations::Mitigations.call?(@api, { "method" => "POST", "path" => "/services/web/scale", "body" => { "instances" => 1 } })
    assert_not Integrations::Mitigations.call?(@api, { "method" => "POST", "path" => "services/web/scale", "body" => { "instances" => 5 } })
    assert_not Integrations::Mitigations.call?(@api, { "method" => "POST", "path" => "services/other/scale", "body" => { "instances" => 1 } }),
               "a service whose count the map does not hold is not taken for one"
    assert_not Integrations::Mitigations.call?(@api, { "method" => "GET", "path" => "services/web" })
  end

  test "a call to a general tool that is one is kept with the default time as it runs" do
    alice = workspace_memberships(:alice_workspace_one)
    conversation = Conversation.start_personal!(workspace: @workspace, member: alice)
    turn = Conversation::Turn.new(conversation, asker: alice)
    chat = conversation.chat_record
    arguments = { "method" => "POST", "path" => "services/web/pause", "intent" => "Pause web while the database recovers" }
    chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "").ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: @api.model_facing_name, arguments: arguments)
    chat.request_decisions!([ "call_1" ])

    Chat::Safeguards.prepare!(turn, [ chat.tool_calls.find_by!(tool_call_id: "call_1") ])

    mitigation = Chat::Mitigation.for_call(chat, "call_1")
    assert_equal Chat::Mitigation::DEFAULT_MINUTES, mitigation.duration_minutes
    assert_equal "Pause web while the database recovers", mitigation.title
  end
end
