require "test_helper"

class FirefightAi::PunctuationTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FirefightAi::AgentLoop.any_instance.stubs(:run).returns(:outcome)
  end

  test "Halon is told to write without em dashes or semicolons in a chat, an investigation and an incident channel" do
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

    assert_includes instructions, FirefightAi::Punctuation::RULE
    assert_includes FirefightAi::Investigator.new(@workspace, inferable: nil).send(:system_prompt), FirefightAi::Punctuation::RULE
    assert_includes FirefightAi::IncidentResponder.new(@workspace).send(:system_prompt), FirefightAi::Punctuation::RULE
  end
end
