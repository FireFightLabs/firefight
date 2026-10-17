require "test_helper"

# What a chat's turn costs the database while the model works. A turn builds its tool catalogue once and shares it with
# everything that reads it, and a turn of many tool calls costs each call the same as a turn of a few.
class Conversation::TurnQueriesTest < ActiveSupport::TestCase
  # What a call through a connection and a call to one of Firefight's own tools cost together, writes included. It was 50
  # when every skill reminder read the skills, the tools and the chat's calls again.
  PER_STEP = 49
  # Reading the connection tools or the skills whole. A check that one tool is still switched on, and the comparison of
  # connections before each model call, read less and are not counted.
  WHOLE_READS = /AS t0_r0\b.*FROM "integration_tools"|FROM "chat_custom_skills"|SELECT DISTINCT "integrations"."provider"/

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    stub_post_message
    stub_agent_session
    RubyLLM.config.stubs(:openai_api_key).returns("sk-test")
    Conversation::Checks.any_instance.stubs(:all).returns([])
    FirefightAi.stubs(:tool_search?).returns(false)
    FirefightAi.stubs(:fits_up_front?).returns(false)
    # Resolved grants are cached, as in production, so what is counted is what a turn sends there.
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    fake = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake", slug: "fake")
    fake.integration_environments.create!(credentials: { token: "x" }.to_json)
    @tool = fake.tools.create!(name: "echo_text", description: "Echoes", params_schema: { "type" => "object" }, enabled: true, read_only: true)
    @group = Chat::Tools::Groups.of_connection(fake)
    Integrations::NativePack.stubs(:for).with("fake").returns(FakeNativePack)
    Integrations::NativeExecutor.stubs(:call).returns("content" => [ { "type" => "text", "text" => "ok" } ])
  end

  test "a turn builds its catalogue once, however many tools it opens and calls" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    turn = Conversation::Turn.new(conversation, asker: @member)
    Conversation::Turn.stubs(:new).returns(turn)
    built = Chat::Tools.build_catalog(turn)
    Chat::Tools.expects(:build_catalog).with(turn).once.returns(built)

    turn_of(4, conversation)

    called = conversation.chat.tool_calls.includes(:result).where(name: [ @tool.model_facing_name, FirefightTools::SEARCH_INCIDENTS.to_s ])
    assert_equal 8, called.size
    assert(called.none?(&:failed), called.map { |call| call.result&.content }.join("\n"))
  end

  test "a turn reads the workspace's tools and skills the same number of times for many calls as for a few" do
    turn_of(2)
    few = tool_reads { turn_of(2) }
    many = tool_reads { turn_of(8) }

    assert_equal few, many
  end

  test "a turn of many tool calls costs each step the same as a turn of a few" do
    turn_of(2)
    few = queries_sent { turn_of(2) }
    many = queries_sent { turn_of(8) }

    per_step = (many.size - few.size) / 6.0
    assert_operator per_step, :<=, PER_STEP, "#{per_step} queries a step:\n#{repeated_queries(many)}"
  end

  private

  # A turn whose model opens Firefight's incident tools and the connection's, then calls the connection's tool and one of
  # Firefight's own that a skill covers count times, each pair in a step of its own, then answers.
  def turn_of(count, conversation = Conversation.start_personal!(workspace: @workspace, member: @member))
    opening = { "call_open_ir" => call("call_open_ir", Chat::Tools::Open.tool_name, "group" => Chat::Tools::Groups::INCIDENT_RESPONSE),
                "call_open_c" => call("call_open_c", Chat::Tools::Open.tool_name, "group" => @group) }
    steps = Array.new(count) do |index|
      { "call_c#{index}" => call("call_c#{index}", @tool.model_facing_name, {}),
        "call_f#{index}" => call("call_f#{index}", FirefightTools::SEARCH_INCIDENTS.to_s, "query" => "checkout #{index}") }
    end
    replies = [ opening, *steps ].map { |calls| llm_reply(tool_calls: calls, finish_reason: :tool_calls) } + [ llm_reply(content: "Checkout is fine.") ]
    stubbed = RubyLLM::Provider.any_instance.stubs(:complete).returns(replies.first)
    replies.drop(1).each { |reply| stubbed = stubbed.then.returns(reply) }
    conversation.ask!("Why is checkout slow?")
    Conversation::Runner.new(conversation, asker: @member).run
  end

  def call(id, name, arguments) = RubyLLM::ToolCall.new(id: id, name: name.to_s, arguments: arguments)

  # How many times the block read the workspace's connection tools whole or its skills, from the query cache or not.
  def tool_reads(&) = queries_sent(cached: true, transactions: true, &).grep(WHOLE_READS).size
end
