require "test_helper"

# A general tool that both reads and changes, such as Cloudflare's execute, offers a chat its guard's reading shape beside
# its own. A read written that way is Firefight's own request, so it never asks and no approval rule holds it, while a
# script someone wrote keeps asking as any change does.
class Chat::Tools::StructuredReadsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: member)
    @turn = Conversation::Turn.new(@conversation, asker: member)
    @chat = @conversation.chat_record
    cloudflare = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                 settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    cloudflare.integration_environments.create!
    @execute = cloudflare.tools.create!(name: "execute", description: "Call the API", enabled: true, read_only: false,
                                        params_schema: { "type" => "object", "properties" => { "code" => { "type" => "string" } }, "required" => [ "code" ] })
    @chat.messages.create!(role: Chat::Message::ROLE_USER, content: "which zones do we have?")
  end

  test "a chat is offered method and path beside code, and neither shape is required" do
    schema = execute.parameters_schema

    assert_equal [ *%w[code method path query graphql variables body account_id], Integration::Tool::ENVIRONMENT_ARG ].sort, (schema["properties"].keys - [ Chat::Tools::INTENT_ARG, Chat::Tools::LookFirst::BECAUSE ]).sort
    assert_not_includes Array(schema["required"]), "code"
    assert_includes execute.description, "To read, pass method and path"
  end

  test "a read written as method and path runs at once as Firefight's own script, and is a read everywhere" do
    given = { "method" => "GET", "path" => "/zones", "query" => { "per_page" => 50 }, "intent" => "List the zones" }
    call = asked!("call_zones", given)

    assert execute.approval_resolver.call(call), "a read never asks"
    assert Integrations::ReadGuards.reads?(@execute, given.except("intent"))
    assert_equal Chat::Tools::KIND_READ, Chat::Tools.kind(@execute.model_facing_name, @workspace, given)
    assert_equal Ability::Action::RISK_READ, @execute.ability_action.risk_of(Integrations::ReadGuards::Cloudflare.reading("execute", given))

    Integrations::McpExecutor.expects(:call).with { |arguments:, **| arguments == { "code" => 'async () => cloudflare.request({"method":"GET","path":"/zones","query":{"per_page":50}})' } }
                             .returns("content" => [ { "type" => "text", "text" => "2 zones" } ])
    assert_match "2 zones", execute.call(tool_call: call, **given.symbolize_keys)
  end

  test "an approval rule written for execute holds its changes and never a read in the reading shape" do
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_APPROVALS, name: "Approvals")
    policy.policy_rules.create!(priority: 1, conditions: [ { field: "risk_level", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ "write" ] } ],
                                outcome: { "require" => { "role" => WorkspaceMembership.roles[:admin], "count" => 1 } })
    read = Integrations::ReadGuards::Cloudflare.reading("execute", "method" => "GET", "path" => "/zones")
    script = { "code" => "async () => cloudflare.request({ method: 'DELETE', path: '/zones/abc' })" }
    action = @execute.ability_action

    assert_nil AbilityGateway.approval_requirement(@workspace, action, @execute.action_key, {}, {}, params: read)
    assert AbilityGateway.approval_requirement(@workspace, action, @execute.action_key, {}, {}, params: script).present?
  end

  test "a script someone wrote keeps asking once it names a read, and a change in the reading shape is refused rather than run" do
    read = { "method" => "GET", "path" => "/zones" }
    @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "").ruby_llm_tool_calls.create!(
      tool_call_id: "call_zones", name: @execute.model_facing_name, arguments: read
    ).update!(result: @chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: "zone abc"))
    because = [ "#{@execute.model_facing_name}: zone abc is the stale one" ]
    script = { "code" => "async () => cloudflare.request({ method: 'DELETE', path: '/zones/abc' })", "intent" => "Delete the zone", "because" => because }

    assert_nil execute.approval_resolver.call(asked!("call_script", script)), "a script that changes something asks as before"

    Integrations::McpExecutor.expects(:call).never
    delete = { "method" => "DELETE", "path" => "/zones/abc", "because" => because }
    answer = execute.call(tool_call: asked!("call_delete", delete), **delete.symbolize_keys)
    assert_equal [ true, Chat::StepOutcome::FAILURE_REFUSED ], @chat.tool_calls.where(tool_call_id: "call_delete").pick(:failed, :failure_kind)
    assert_includes answer, Integrations::ReadGuards::Cloudflare::DESCRIPTION
  end

  private

  def execute = Chat::Tools.catalog(@turn).find { |entry| entry.name == @execute.model_facing_name }.tool

  def asked!(tool_call_id, arguments)
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    message.ruby_llm_tool_calls.create!(tool_call_id: tool_call_id, name: @execute.model_facing_name, arguments: arguments)
    RubyLLM::ToolCall.new(id: tool_call_id, name: @execute.model_facing_name, arguments: arguments)
  end
end
