require "test_helper"

class FirefightAi::ResponderTest < ActiveSupport::TestCase
  setup do
    # These chats are mocks, so pointing one at its payer is left out.
    FirefightAi.stubs(:bind)
    @workspace = workspaces(:slack_workspace_one)
    FirefightAi::AgentLoop.any_instance.stubs(:run).returns(:outcome)
  end

  test "a turn is told the manual, then who it acts for" do
    instructions = nil
    chat = chat_double { |text| instructions = text }

    answer(chat)

    assert instructions.start_with?(FirefightAi::Responder::ROLE)
    assert_includes instructions, FirefightAi::Manual::THINKING
    assert_includes instructions, FirefightAi::Manual::TOOLS
    assert_includes instructions, FirefightAi::Responder::ANSWERING
    assert instructions.end_with?("You are acting for Ada.")
  end

  # Seen in a real chat, asked to assign a role, the agent typed "lead" instead of reading the workspace's roles.
  test "a chat is told it may do what the person may, and to do it rather than explain it" do
    assert_match "with exactly the permissions they have", FirefightAi::Responder::ROLE
    assert_match "Do it rather than explaining how", FirefightAi::Responder::ROLE
  end

  # A chat grows with every question, and each turn resends all of it.
  test "a turn asks the provider to cache what it has already read" do
    chat = chat_double
    chat.expects(:with_caching)

    answer(chat)
  end

  test "a chat told a model runs on it, and its prompt version names the wording without the per chat context" do
    chosen = FirefightAi::ModelChoice.new(model: "gpt-5.6-luna", provider: "openai")
    FirefightAi.expects(:model_for).never

    responder = FirefightAi::Responder.new(@workspace, inferable: nil, model: chosen)

    assert_equal chosen, responder.ai_model
    assert_equal responder.prompt_version, FirefightAi::Responder.new(@workspace, inferable: nil, model: chosen).prompt_version
    refute_equal responder.prompt_version, FirefightAi::Responder.new(@workspace, inferable: nil, model: chosen, output_style: "Use Slack markup.").prompt_version
  end

  private

  def answer(chat)
    FirefightAi::Responder.new(@workspace, inferable: nil).run(
      chat: chat, tools: [], context: "You are acting for Ada.",
      budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 50, max_turns: 10)
    )
  end

  def chat_double(&told)
    chat = mock("chat")
    chat.stubs(:to_llm).returns(stub(messages: []))
    chat.stubs(:with_tools)
    chat.stubs(:with_caching)
    told ? chat.expects(:with_instructions).with { |text| told.call(text) } : chat.stubs(:with_instructions)
    chat
  end
end
