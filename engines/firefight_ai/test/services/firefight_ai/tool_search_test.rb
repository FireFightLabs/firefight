require "test_helper"

# How tools and the cache reach a saved chat on each provider, read off the request RubyLLM would send, and what happens
# to both when the chat moves to another provider mid-way.
class FirefightAi::ToolSearchTest < ActiveSupport::TestCase
  include FakeProviderHelper

  # A tool by name, which answers with its own name.
  class Lookup < RubyLLM::Tool
    description "Reads one thing"

    def initialize(tool_name)
      super()
      @tool_name = tool_name
    end

    def name = @tool_name

    def parameters_schema = { "type" => "object", "properties" => {} }

    def call(tool_call: nil, **) = "#{@tool_name} read it"
  end

  setup do
    FirefightAi::ToolSearch.forget!
    FakeProviderHelper::Adapter.reset!
    @workspace = workspaces(:slack_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
  end

  teardown { FirefightAi::ToolSearch.forget! }

  test "Anthropic and OpenAI search deferred tools themselves, OpenRouter and Bedrock send every tool whole" do
    assert FirefightAi.tool_search?(anthropic)
    assert FirefightAi.tool_search?(openai)
    assert_not FirefightAi.tool_search?(openrouter)
    assert_not FirefightAi.tool_search?(bedrock)
  end

  test "a choice no request can be rendered for is answered no, and asked again once it can be" do
    keyless = FirefightAi::ModelChoice.new(model: "claude-haiku-4-5", provider: "anthropic", context: fake_provider_context(anthropic_api_key: nil))

    assert_not FirefightAi.tool_search?(keyless)
    assert FirefightAi.tool_search?(anthropic), "the same provider and model with a key is probed afresh"
  end

  test "where the provider searches, the long tail is deferred behind its search tool and the core is held whole" do
    chat = ready(anthropic, deferred: [ Lookup.new("github_list_issues"), Lookup.new("core_read") ])
    tools = chat.to_llm.render[:tools].index_by { |tool| tool[:name] || tool[:type] }

    assert_nil tools["core_read"][:defer_loading], "a tool held whole stays whole even when it is offered deferred too"
    assert tools["github_list_issues"][:defer_loading]
    assert(tools.keys.any? { |key| key.to_s.start_with?("tool_search") })
  end

  test "where the provider does not search, nothing is deferred and the agent opens groups as before" do
    chat = ready(openrouter, deferred: [ Lookup.new("github_list_issues") ])

    assert_empty chat.to_llm.deferred_tools
    assert_equal [ "core_read" ], chat.to_llm.tools.keys.map(&:to_s)
  end

  test "the instructions end in a cache boundary that lasts as long as asked, after the tool definitions" do
    hour = ready(anthropic, cache_ttl: FirefightAi::LONG_CACHE).to_llm.render
    default = ready(anthropic, conversation: Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))).to_llm.render

    assert_equal({ type: "ephemeral", ttl: "1h" }, hour[:system].last[:cache_control])
    assert_equal({ type: "ephemeral" }, default[:system].last[:cache_control])
    assert hour[:cache_control], "the conversation as it grows is cached too"
  end

  test "a chat that moves to a provider without search loses its deferred tools and keeps the rest" do
    chat = ready(anthropic, deferred: [ Lookup.new("github_list_issues") ])

    FirefightAi.present_tools(chat, openrouter)

    assert_empty chat.to_llm.deferred_tools
    assert_equal [ "core_read" ], chat.to_llm.tools.keys.map(&:to_s)
  end

  # RubyLLM 2.1 replays a message without the native content another model produced, so the backup and the chat picker
  # carry a chat on from the middle of a tool round with nothing of ours stripping it.
  test "a chat switched to another provider mid tool round sends the round on without the first provider's thinking" do
    chat = ready(anthropic)
    chat.add_message(role: :user, content: "Read it")
    answer_with({
      id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-4-5", stop_reason: "tool_use",
      content: [ { type: "thinking", thinking: "I should read core first", signature: "sig-from-anthropic" },
                 { type: "tool_use", id: "toolu_1", name: "core_read", input: {} } ],
      usage: { input_tokens: 20, output_tokens: 10 }
    })
    chat.step
    chat.step

    FirefightAi.bind(chat, openai)
    answer_with({ id: "resp_1", object: "response", status: "completed", model: "gpt-4o",
                  output: [ { type: "message", role: "assistant", content: [ { type: "output_text", text: "Read." } ] } ],
                  usage: { input_tokens: 30, output_tokens: 2 } })
    reply = chat.step

    sent = sent_requests.last
    assert_match %r{/responses\z}, sent[:url]
    assert_not_includes sent[:body].to_json, "sig-from-anthropic"
    assert_not_includes sent[:body].to_json, "I should read core first"
    call = sent[:body]["input"].find { |item| item["type"] == "function_call" }
    output = sent[:body]["input"].find { |item| item["type"] == "function_call_output" }
    assert_equal [ "core_read", "toolu_1" ], [ call["name"], call["call_id"] ]
    assert_equal "core_read read it", output["output"]
    assert_equal "Read.", reply.content
    assert_equal "sig-from-anthropic", chat.messages.find_by(role: Chat::Message::ROLE_ASSISTANT).thinking_signature, "the record keeps what Anthropic said"
  end

  private

  def anthropic = FirefightAi::ModelChoice.new(model: "claude-haiku-4-5", provider: "anthropic", context: fake_provider_context(anthropic_api_key: "sk-ant-test"))

  def openai = FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai", context: fake_provider_context(openai_api_key: "sk-test"))

  def openrouter
    FirefightAi::ModelChoice.new(model: "anthropic/claude-haiku-5.5", provider: "openrouter", context: fake_provider_context(openrouter_api_key: "sk-or-test"))
  end

  def bedrock
    FirefightAi::ModelChoice.new(model: "anthropic.claude-sonnet-4-5-20250929-v1:0", provider: "bedrock",
                                 context: fake_provider_context(bedrock_api_key: "AKIATEST", bedrock_secret_key: "secret", bedrock_region: "us-east-1"))
  end

  def ready(choice, deferred: [], cache_ttl: nil, conversation: @conversation)
    chat = Chat.open!(owner: conversation, workspace: @workspace, model_choice: choice)
    FirefightAi.ready_chat(chat, choice: choice, instructions: "Read before you answer.", tools: [ Lookup.new("core_read") ],
                                 deferred_tools: deferred, cache_ttl: cache_ttl)
  end
end
