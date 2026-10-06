require "test_helper"

class FirefightAi::InvestigatorTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @seed_pack = { "incident" => { "identifier" => "INC-001", "name" => "Checkout failing" } }
    FirefightAi::AgentLoop.any_instance.stubs(:run).returns(:outcome)
  end

  test "a fresh run is told how to work and handed the facts" do
    chat = chat_double(messages: [])
    instructions = nil
    chat.expects(:with_instructions).with { |text| instructions = text }
    chat.expects(:add_message).with { |message| @opening = message[:content] }

    investigator.run(chat: chat, tools: [], seed_pack: @seed_pack, budget: budget, answered: -> { false })

    assert_match "conclude", instructions
    assert_match FirefightAi::Evidence::RULE, instructions
    assert_match "INC-001", @opening
  end

  test "a run is told to look before asking and to find a resource on the map before any provider tool" do
    prompt = FirefightAi::Investigator.system_prompt

    assert_includes prompt, FirefightAi::LookFirstRule::RULE
    assert_includes prompt, FirefightAi::LookFirstRule::MAP_RULE
    assert_includes prompt, FirefightAi::LookFirstRule::CONNECTION_RULE
    assert_includes prompt, FirefightAi::LookFirstRule::CHANGED_RULE
    assert_includes prompt, FirefightAi::LookFirstRule::CAUSE_RULE
  end

  # Seen in a real chat, Halon searched the web and guessed a provider's path three times for a call that does not exist.
  test "a run reads the provider's own guides before the web, and never retries a guessed call that answered 404 or 405" do
    prompt = FirefightAi::Investigator.system_prompt

    assert_includes prompt, FirefightAi::LookFirstRule::API_GUIDE_RULE
    assert_includes prompt, FirefightAi::LookFirstRule::GUESSED_CALL_RULE
  end

  test "a run is told to start from the resources the facts list, with the map tools" do
    prompt = FirefightAi::Investigator.system_prompt

    assert_includes prompt, FirefightAi::Investigator::MAP_START
    assert_match "Start from them with the map tools: get_resource for one", prompt
  end

  test "a resumed run is not handed the facts a second time" do
    chat = chat_double(messages: [ RubyLLM::Message.new(role: :user, content: "Investigate this incident") ])
    chat.expects(:with_instructions)
    chat.expects(:add_message).never

    investigator.run(chat: chat, tools: [], seed_pack: @seed_pack, budget: budget, answered: -> { false })
  end

  # One agent resends its whole history every turn, so without the provider's cache a long run pays for it each time.
  test "a run asks the provider to cache what it has already read" do
    chat = chat_double(messages: [])
    chat.expects(:with_caching)

    investigator.run(chat: chat, tools: [], seed_pack: @seed_pack, budget: budget, answered: -> { false })
  end

  test "a client error stops at the engine boundary" do
    chat = chat_double(messages: [])
    chat.stubs(:with_instructions).raises(RubyLLM::RateLimitError.new("slow down"))

    error = assert_raises(FirefightAi::TransientError) do
      investigator.run(chat: chat, tools: [], seed_pack: @seed_pack, budget: budget, answered: -> { false })
    end
    assert_equal "RateLimitError", error.reason
  end

  private

  def investigator
    FirefightAi::Investigator.new(@workspace, inferable: @incident)
  end

  def chat_double(messages:)
    chat = mock("chat")
    chat.stubs(:to_llm).returns(stub(messages: messages))
    chat.stubs(:with_tools)
    chat.stubs(:with_caching)
    chat.stubs(:with_instructions)
    chat.stubs(:add_message)
    chat
  end

  def budget
    FirefightAi::AgentLoop::Budget.new(max_spend_cents: 400, max_turns: 10)
  end
end
