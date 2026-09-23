require "application_system_test_case"

class AgentIntegrationCardTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "a category of integrations is a table, and Connect opens the dialog that comes back to the chat" do
    datadog = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", settings: { "server_url" => "https://dd.example/mcp" }
    )
    datadog.integration_environments.create!
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    conversation.ask!("what can we connect for logs")
    reply = conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: Mcp::Tools::LIST_INTEGRATIONS, arguments: { "category" => "telemetry" })
    conversation.chat.add_message(role: :tool, content: "{}", tool_call_id: "call_1")
    conversation.note!("Datadog is connected already. Pick one below to add another.")
    conversation.reply_delivered!

    visit agent_chat_path(conversation)

    within("section[aria-label='Telemetry integrations']") do
      assert_text "Datadog"
      assert_text "Connected"
      assert_text "New Relic"
      within("li", text: "New Relic") { click_button "Connect" }
    end

    assert_text "Connect New Relic"
  end

  # Seen in review. Manage only reached the page, so the connection itself had to be found again.
  test "Manage opens that connection's details, and the details can be shared by their address" do
    datadog = @workspace.integrations.create!(
      kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", settings: { "server_url" => "https://dd.example/mcp" }
    )
    datadog.integration_environments.create!
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    conversation.ask!("what telemetry do we have")
    reply = conversation.chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: Mcp::Tools::LIST_INTEGRATIONS, arguments: { "category" => "telemetry" })
    conversation.chat.add_message(role: :tool, content: "{}", tool_call_id: "call_1")
    conversation.note!("Datadog is connected.")
    conversation.reply_delivered!

    visit agent_chat_path(conversation)
    within("li", text: "Datadog") { click_link "Manage" }

    assert_text "Connection details"
    assert_includes current_url, "#{Integration::DETAILS_QUERY_PARAM}=#{datadog.id}"

    find("body").send_keys(:escape)
    assert_no_text "Connection details"
    assert_nil URI(current_url).query

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => datadog.id)
    assert_text "Connection details"
  end

  test "a link naming a provider opens its connect dialog" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "linear")

    assert_text "Connect Linear"
  end
end
