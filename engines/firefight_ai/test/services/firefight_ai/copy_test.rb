require "test_helper"

class FirefightAi::CopyTest < ActiveSupport::TestCase
  setup do
    # These chats are mocks, so pointing one at its payer is left out.
    FirefightAi.stubs(:bind)
    @workspace = workspaces(:slack_workspace_one)
    FirefightAi::AgentLoop.any_instance.stubs(:run).returns(:outcome)
  end

  test "Halon is told how to write in a chat, an investigation and an incident channel, with no em dash or semicolon, no pronoun guessed from a name and a person's words quoted exactly" do
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

    assert_includes instructions, FirefightAi::Copy::RULE
    assert_includes FirefightAi::Investigator.new(@workspace, inferable: nil).send(:system_prompt), FirefightAi::Copy::RULE
    assert_includes FirefightAi::IncidentResponder.new(@workspace).send(:system_prompt), FirefightAi::Copy::RULE
  end

  test "a check that could not run is listed under Could not run here and never called blocked, in a chat, an investigation and a review" do
    assert_includes FirefightAi::Copy::RULE, FirefightAi::Copy::NOT_RUN
    assert_includes FirefightAi::Copy::NOT_RUN, "goes under Could not run here"
    assert_includes FirefightAi::Copy::NOT_RUN, "Never call it blocked or a blocker"
    assert_includes FirefightAi::Investigator.new(@workspace, inferable: nil).send(:system_prompt), FirefightAi::Copy::NOT_RUN
    assert_includes FirefightAi::ChangeReviewer::PROMPT, FirefightAi::Copy::NOT_RUN
  end
end
