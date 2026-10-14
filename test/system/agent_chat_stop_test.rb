require "application_system_test_case"

# Seen live: Stop on a chat whose checks from outside were still running said Stopping for minutes, reloaded the whole
# chat, and a reload showed Halon working again with its timer back at zero.
class AgentChatStopTest < ApplicationSystemTestCase
  # The test adapter only records broadcasts, and this test needs the browser to receive one.
  setup do
    @cable = ActionCable.server.config.cable
    ActionCable.server.config.cable = { "adapter" => "async" }
    ActionCable.server.restart
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    # The sign in helper stubs the controller, not the session the socket reads, so the socket is stubbed too.
    ApplicationCable::Connection.any_instance.stubs(:signed_in_user).returns(users(:alice))
  end

  teardown do
    ActionCable.server.config.cable = @cable
    ActionCable.server.restart
  end

  test "Stop keeps the chat where it is, a reload still says Stopping, and the answer ends with its checks stopped" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!("look into faylee.app and tell me if indexing is on")
    conversation.update!(answer_owed_since: 90.seconds.ago)

    visit agent_chat_path(conversation)
    assert_text "look into faylee.app"
    assert_text(/Working\s+1m 3\d\.\ds/)
    page.execute_script("window.stillTheSamePage = true")

    find("button[aria-label='Stop']").click

    assert_toast Conversation::STOPPING
    assert_selector "[aria-label='Prompt'][placeholder='Stopping']"
    assert page.evaluate_script("window.stillTheSamePage === true"), "the page stayed as it was"
    assert conversation.chat.reload.stop_requested?
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-chat-stopping.png"))

    visit agent_chat_path(conversation)
    assert_selector "[aria-label='Prompt'][placeholder='Stopping']"
    assert_text(/Working\s+1m 3\d\.\ds/)
    assert_no_selector "button[aria-label='Stop']"

    stopped_at_the_tool(conversation)

    assert_text Conversation::Runner::STOPPED
    assert_selector "[aria-label='Prompt'][placeholder='Ask the agent, or @ an incident']"
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-chat-stopped.png"))
    find("button", text: /Worked for/).click
    assert_text "Check from outside"
    assert_selector "span.sr-only", text: "Stopped", visible: :all, count: 2
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-chat-stopped-steps.png"))
  end

  private

  # The worker hears the stop while the first check runs, and the turn ends as stopped, as Conversation::Runner does.
  def stopped_at_the_tool(conversation)
    responder = Object.new
    responder.define_singleton_method(:ai_model) { FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil) }
    chat = conversation.chat
    responder.define_singleton_method(:run) do |**arguments|
      asking = chat.add_message(role: :assistant, content: "")
      asking.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: Chat::Tools::OutsideCheck::NAME, arguments: { "url" => "https://faylee.app" })
      asking.ruby_llm_tool_calls.create!(tool_call_id: "call_2", name: Chat::Tools::OutsideCheck::NAME, arguments: { "url" => "https://www.faylee.app" })
      arguments[:on_step].call(FirefightAi::AgentLoop::Step.new(key: "call_1", tool: Chat::Tools::OutsideCheck::NAME,
                                                                status: FirefightAi::AgentLoop::STEP_RUNNING, arguments: { "url" => "https://faylee.app" }))
      FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_CANCELED, turns_used: 1, spent_micros: 0)
    end
    FirefightAi::Responder.stubs(:new).returns(responder)
    Chat.any_instance.stubs(:stop_requested?).returns(false)
    Conversation::Runner.new(conversation.reload, asker: @member).run
  end
end
