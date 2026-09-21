require "test_helper"

class FirefightAi::ResponderTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FirefightAi::AgentLoop.any_instance.stubs(:run).returns(:outcome)
  end

  # Seen in a real chat, an answer that opened with "The workspace setup tools opened successfully."
  test "the agent is told to keep how it works to itself" do
    chat = mock("chat")
    chat.stubs(:to_llm).returns(stub(messages: []))
    chat.stubs(:with_tools)
    chat.stubs(:with_caching)
    instructions = nil
    chat.expects(:with_instructions).with { |text| instructions = text }

    FirefightAi::Responder.new(@workspace, inferable: nil).run(
      chat: chat, tools: [], context: "You are acting for Ada.",
      budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 50, max_turns: 10)
    )

    assert_match "Never mention your tools", instructions
  end

  # A chat grows with every question, and each turn resends all of it.
  test "a turn asks the provider to cache what it has already read" do
    chat = mock("chat")
    chat.stubs(:to_llm).returns(stub(messages: []))
    chat.stubs(:with_tools)
    chat.stubs(:with_instructions)
    chat.expects(:with_caching)

    FirefightAi::Responder.new(@workspace, inferable: nil).run(
      chat: chat, tools: [], context: "You are acting for Ada.",
      budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 50, max_turns: 10)
    )
  end
end
