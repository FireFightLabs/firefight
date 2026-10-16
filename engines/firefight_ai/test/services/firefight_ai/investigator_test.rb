require "test_helper"

class FirefightAi::InvestigatorTest < ActiveSupport::TestCase
  setup do
    # These chats are mocks, so pointing one at its payer is left out.
    FirefightAi.stubs(:bind)
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @seed_pack = { "incident" => { "identifier" => "INC-001", "name" => "Checkout failing" } }
    FirefightAi::AgentLoop.any_instance.stubs(:run).returns(:outcome)
  end

  test "a fresh run is told the manual and how a run works, and handed the facts with how to read them" do
    chat = chat_double(messages: [])
    instructions = nil
    chat.expects(:with_instructions).with { |text| instructions = text }
    chat.expects(:add_message).with { |message| @opening = message[:content] }

    investigator.run(chat: chat, tools: [], seed_pack: @seed_pack.merge("resources" => [ { "name" => "web" } ]), budget: budget, answered: -> { false })

    assert instructions.start_with?(FirefightAi::Investigator::ROLE)
    assert_includes instructions, FirefightAi::Investigator::RUN
    assert_includes instructions, FirefightAi::Manual::RUN_TOOLS
    assert_match "INC-001", @opening
    assert_includes @opening, FirefightAi::Facts::READING.fetch("resources")
  end

  test "a run cites steps, records its theories and ends only with conclude" do
    run = FirefightAi::Investigator::RUN

    assert_match "Every tool result carries a step number", run
    assert_match "record_hypothesis as you form it", run
    assert_match "conclude ends the run", run
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

  # A run's tools, instructions and facts never change, so each ends in a boundary, written once and read on every turn
  # after it, with the provider's default lifetime since a run's turns follow each other within seconds.
  test "the instructions and the facts each end in a cache boundary of the default lifetime" do
    chat = chat_double(messages: [])
    chat.expects(:with_instructions).with(FirefightAi::Investigator.system_prompt, cache_until_here: true)
    chat.expects(:add_message).with { |role:, cache_until_here:, **rest| role == :user && cache_until_here == true && !rest.key?(:cache_ttl) }

    investigator.run(chat: chat, tools: [], seed_pack: @seed_pack, budget: budget, answered: -> { false })
  end

  test "a scheduled check takes the purse and the backup the run hands it, as an investigation does" do
    chat = chat_double(messages: [])
    shared = FirefightAi::AgentLoop::Purse.new
    backup = ->(*) { }
    FirefightAi::AgentLoop.expects(:new).with { |purse: nil, on_backup: nil, **| purse.equal?(shared) && on_backup.equal?(backup) }
                          .returns(stub(run: FirefightAi::AgentLoop::Outcome.new(status: :answered, turns_used: 0, spent_micros: 0)))

    FirefightAi::Monitor.new(@workspace, inferable: @incident).run(chat: chat, tools: [], seed_pack: @seed_pack, budget: budget, answered: -> { false },
                                                                   purse: shared, on_backup: backup)
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
    chat.stubs(:to_llm).returns(stub(messages: messages, with_temperature: nil, with_tool_options: nil))
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
