require "test_helper"

class FirefightAi::ResponderTest < ActiveSupport::TestCase
  setup do
    # These chats are mocks, so pointing one at its payer is left out.
    FirefightAi.stubs(:bind)
    @workspace = workspaces(:slack_workspace_one)
    FirefightAi::AgentLoop.any_instance.stubs(:run).returns(:outcome)
  end

  test "a turn is told the manual and what holds for the whole chat, and who it acts for after the chat" do
    instructions = nil
    chat = chat_double { |text| instructions = text }
    FirefightAi::AgentLoop.expects(:new).with { |**options| options[:context] == "#{FirefightAi::Responder::CONTEXT_HEADING}\nYou are acting for Ada." }
                          .returns(stub(run: :outcome))

    answer(chat, stable_context: "The workspace's handbook.")

    assert instructions.start_with?(FirefightAi::Responder::ROLE)
    assert_includes instructions, FirefightAi::Manual::THINKING
    assert_includes instructions, FirefightAi::Manual::TOOLS
    assert_includes instructions, FirefightAi::Responder::ANSWERING
    assert instructions.end_with?("The workspace's handbook.")
    assert_not_includes instructions, "You are acting for Ada."
  end

  test "the heading the context opens with is part of the wording the version names" do
    responder = FirefightAi::Responder.new(@workspace, inferable: nil)
    shipped = responder.prompt_version

    stub_const(FirefightAi::Responder, :CONTEXT_HEADING, "Another heading:") do
      refute_equal shipped, responder.prompt_version
    end
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

  test "a chat asks its model again for a reply it could not read, and a second one comes back as a reply nobody could read" do
    FirefightAi::AgentLoop.expects(:new).with { |**options| options[:retry_malformed] == true }.returns(stub(run: :outcome))
    answer(chat_double)

    FirefightAi::AgentLoop.unstub(:new)
    FirefightAi::AgentLoop.any_instance.stubs(:run).raises(RubyLLM::ToolCallParseError.new(finish_reason: :tool_calls))
    raised = assert_raises(FirefightAi::UnreadableReply) { answer(chat_double) }
    assert_kind_of FirefightAi::TerminalError, raised
    assert_equal "ToolCallParseError", raised.reason
  end

  private

  def answer(chat, stable_context: nil)
    FirefightAi::Responder.new(@workspace, inferable: nil).run(
      chat: chat, tools: [], context: "You are acting for Ada.", stable_context: stable_context,
      budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 50, max_turns: 10)
    )
  end

  def chat_double(&told)
    chat = mock("chat")
    chat.stubs(:to_llm).returns(stub(messages: [], with_temperature: nil))
    chat.stubs(:with_tools)
    chat.stubs(:with_caching)
    told ? chat.expects(:with_instructions).with { |text| told.call(text) } : chat.stubs(:with_instructions)
    chat
  end
end
