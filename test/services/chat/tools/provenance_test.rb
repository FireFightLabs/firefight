require "test_helper"

# What Halon read from outside before a change is kept with it, and the change warns only when that text holds one of the
# change's own values, while Allow for the rest of this chat never covers it either way.
class Chat::Tools::ProvenanceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @chat = @conversation.chat_record
    @turn = Conversation::Turn.new(@conversation, asker: @member)
  end

  test "a value any change of its kind holds is generic, a name, an id or an address is the change's own" do
    %w[POST delete true null pause json 8080 4096 1.5 -12 Ok].each { |value| assert_not Chat::Tools::Provenance.specific?(value), value }
    %w[dev-web nf-compute-100-4 checkout srv_8a7cf66a https://shop.example.com 10.0.4.17 123456].each do |value|
      assert Chat::Tools::Provenance.specific?(value), value
    end
  end

  test "docs that hold only the request's method say nothing about where the change came from, so there is no warning" do
    read!("call_doc", Chat::Tools::Docs::READ, { "provider" => "northflank", "page" => "api/services" }, "POST /v1/projects/{project}/services/{service}/pause")
    ask!("call_pause", { "method" => "POST", "path" => "services/dev-web/pause" })

    confirmation = recorded("call_pause")

    assert_nil confirmation.read_lead
    assert_not confirmation.allowable?, "Allow for the rest of this chat still never covers a change asked after outside text"
    assert_equal Chat::Tools::READ_HEADING, confirmation.read_heading
    assert_equal [ [ Chat::Tools.label(Chat::Tools::Docs::READ, { "provider" => "northflank", "page" => "api/services" }), Chat::Tools::READ_EARLIER ] ],
                 confirmation.read_rows
  end

  test "outside text holding the change's own value warns and names where it came from" do
    read!("call_doc", Chat::Tools::Docs::READ, { "provider" => "northflank", "page" => "plans" }, "Plans: nf-compute-100-2, nf-compute-100-4")
    read!("call_web", Chat::Tools::Web::SEARCH, { "query" => "plans" }, "Upgrade to nf-compute-100-4 now")
    ask!("call_scale", { "method" => "POST", "path" => "services/job/scale", "body" => { "deploymentPlan" => "nf-compute-100-4" } })

    confirmation = recorded("call_scale")

    assert_equal "Halon read Northflank's docs and the web before asking. Check the reason above is yours.", confirmation.read_lead
    assert_equal "Mentions nf-compute-100-4", confirmation.read_rows.first.last
    assert_not confirmation.allowable?
  end

  test "a value the person wrote is theirs, so outside text holding it does not warn" do
    @chat.messages.create!(role: Chat::Message::ROLE_USER, content: "pause dev-web please")
    read!("call_list", Chat::Tools::Web::READ, { "url" => "https://status.example.com" }, "dev-web is degraded")
    ask!("call_pause", { "method" => "POST", "path" => "dev-web" })

    assert_nil recorded("call_pause").read_lead
  end

  test "an answer from a connection and a file someone attached are named by where they came from" do
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    northflank.integration_environments.create!(credentials: { token: "x" }.to_json).store_fields!("project" => "faylee")
    tool = northflank.tools.create!(name: "api_request", description: "API", read_only: false, enabled: true, params_schema: { "type" => "object" })
    read!("call_get", tool.model_facing_name, { "method" => "GET", "path" => "services" }, "services: dev-web, web")
    ask!("call_pause", { "method" => "POST", "path" => "services/dev-web/pause", "service" => "dev-web" })

    assert_equal "Halon read an answer from #{northflank.display_name} before asking. Check the reason above is yours.", recorded("call_pause").read_lead
  end

  test "a question kept before generic values were left out reads the same as a new one" do
    call = ask!("call_old", { "method" => "POST" }, record: false)
    call.update_columns(provenance: { "sources" => [ { "label" => "Read doc", "found" => [ "POST" ] } ], "others" => 21 })
    assert_nil Chat::Tools.confirmation(call.reload).read_lead
    assert_equal [ [ "Read doc", Chat::Tools::READ_EARLIER ], [ "21 more reads", Chat::Tools::READ_EARLIER ] ], Chat::Tools.confirmation(call).read_rows

    call.update_columns(provenance: { "sources" => [ { "label" => "Read doc", "found" => [ "POST", "dev-web" ] } ], "others" => 0 })
    confirmation = Chat::Tools.confirmation(call.reload)
    assert_equal "Halon read text from outside Firefight before asking. Check the reason above is yours.", confirmation.read_lead
    assert_equal [ [ "Read doc", "Mentions dev-web" ] ], confirmation.read_rows
  end

  private

  def read!(tool_call_id, name, arguments, answer)
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = message.ruby_llm_tool_calls.create!(tool_call_id: tool_call_id, name: name, arguments: arguments)
    call.update!(result: @chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: answer))
  end

  def ask!(tool_call_id, arguments, record: true)
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = message.ruby_llm_tool_calls.create!(tool_call_id: tool_call_id, name: "northflank_api_request", arguments: arguments)
    @chat.request_decisions!([ tool_call_id ])
    Chat::Tools::Provenance.record!(@turn, [ call ]) if record
    call
  end

  def recorded(tool_call_id) = Chat::Tools.confirmation(@chat.tool_calls.find_by!(tool_call_id: tool_call_id))
end
