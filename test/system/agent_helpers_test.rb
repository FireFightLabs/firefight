require "application_system_test_case"

# Halon handed three reads to helpers that ran at the same time. Each shows under the step that started them, with what
# it read and what it reported, or why it has no report.
class AgentHelpersTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @conversation.ask!("Why is checkout slow since 14:00?")
    @chat = @conversation.chat
    reply = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: Chat::Tools::Helpers::NAME, arguments: { "checks" => [
      { "title" => "Logs of checkout", "brief" => "Read checkout's error logs since 14:00 and say which errors are new" },
      { "title" => "Recent deploys", "brief" => "List deploys of checkout and its database since 13:00" },
      { "title" => "Error rate", "brief" => "Compare checkout's error rate since 14:00 with its normal" }
    ] })
    @logs, @deploys, @errors = Chat::Helper.start!(chat: @chat, tool_call_id: "call_1", since: 1.minute.ago, checks: [
      Chat::Helpers::Check.new(title: "Logs of checkout", brief: "Read checkout's error logs", deep: false),
      Chat::Helpers::Check.new(title: "Recent deploys", brief: "List deploys", deep: false),
      Chat::Helpers::Check.new(title: "Error rate", brief: "Compare the error rate", deep: false)
    ])
    read!(@logs, "h_1", Mcp::Tools::SEARCH_INCIDENTS, { "query" => "checkout timeouts" }, "INC-7 checkout timeouts to orders-db")
    read!(@deploys, "h_2", Mcp::Tools::SEARCH_INCIDENTS, { "query" => "deploys" }, "web deploy 4f2a1c at 13:58")
  end

  test "each helper is its own trace under the step, with its report or why it has none in view" do
    @chat.add_message(role: :tool, content: "Helpers reported, 2 of 3.", tool_call_id: "call_1")
    @logs.finish!(Chat::Helper::STATUS_REPORTED, report: "40 timeouts to orders-db since 14:02, none before (steps 2, 3).")
    @deploys.finish!(Chat::Helper::STATUS_REPORTED, report: "web deploy 4f2a1c went out at 13:58, four minutes before the first timeout.")
    @errors.finish!(Chat::Helper::STATUS_FAILED, ended_because: Chat::Helper::OUT_OF_BUDGET)
    @conversation.note!("Checkout slowed after the 13:58 deploy of web, which times out on orders-db.")
    @conversation.reply_delivered!

    visit agent_chat_path(@conversation)
    trace = find("button[aria-expanded]", text: /Worked for/)
    trace.click if trace["aria-expanded"] == "false"

    assert_text "3 checks at once"
    assert_text "Logs of checkout · Reported · 1 step"
    assert_text "40 timeouts to orders-db since 14:02, none before (steps 2, 3)."
    assert_text "Error rate · No report · 0 steps"
    assert_text Chat::Helper::OUT_OF_BUDGET
    assert_no_text "Search incidents"

    find("button", text: "Logs of checkout · Reported").click

    assert_text "Search incidents"
    assert_text "checkout timeouts"
  end

  test "while helpers work, each shows the steps it is taking" do
    visit agent_chat_path(@conversation)

    assert_text "3 checks at once"
    assert_text "Logs of checkout"
    assert_text "checkout timeouts"
    assert_text "deploys"
    assert_text "Reading the brief"
  end

  private

  def read!(helper, id, tool, arguments, said)
    own = Chat.open!(owner: helper, workspace: @workspace, model_choice: FirefightAi::ModelChoice.new(model: "gpt-4o-mini"))
    asked = own.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    asked.ruby_llm_tool_calls.create!(tool_call_id: id, name: tool, arguments: arguments)
    own.add_message(role: :tool, content: said, tool_call_id: id)
  end
end
