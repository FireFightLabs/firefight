require "test_helper"

# Z.AI, MiniMax and Qwen, which RubyLLM does not ship, answered with each provider's own documented shapes, so what goes
# over the wire is what the provider's documentation asks for.
class FirefightAi::ProvidersTest < ActiveSupport::TestCase
  include FakeProviderHelper

  class ReadLogs < RubyLLM::Tool
    description "Reads a service's recent logs"
    parameter :service, description: "The service"

    def name = "read_logs"

    def execute(service:) = "#{service}: 3 timeouts in the last hour"
  end

  SCHEMA = { type: "object", properties: { cause: { type: "string" } }, required: [ "cause" ], additionalProperties: false }.freeze

  setup { FakeProviderHelper::Adapter.reset! }

  test "each is registered with RubyLLM, and its models are priced and sized from the providers' own pages" do
    { "zai" => %w[glm-5.3 glm-5.3-flash], "minimax" => %w[MiniMax-M3 MiniMax-M3.1-Flash], "qwen" => %w[qwen3.8-max qwen3.8-flash] }.each do |slug, models|
      assert RubyLLM::Provider.resolve(slug), "#{slug} is registered"
      models.each do |model|
        assert FirefightAi.priced_for?(model, slug), "#{slug} #{model} is priced"
        assert_equal 1_000_000, FirefightAi.context_window(model, provider: slug)
        assert RubyLLM.models.find(model, provider: slug).supports?(:function_calling), "#{slug} #{model} calls tools"
      end
    end
  end

  # A process reads the table again whenever it changed, and a table last refreshed before these providers were added
  # holds none of their models, which would leave them unpriced until the next refresh.
  test "reading the models table again keeps the registered providers' models, writing in any it does not hold" do
    RubyLLM::ActiveRecord::Model.where(provider: %w[zai minimax qwen]).delete_all
    RubyLLM::ActiveRecord::Model.where(provider: "anthropic").limit(1).update_all(updated_at: 1.minute.from_now)

    FirefightAi.reload_registry_if_changed!

    assert_equal 6, RubyLLM::ActiveRecord::Model.where(provider: %w[zai minimax qwen]).count
    assert FirefightAi.priced_for?("qwen3.8-max", "qwen")
    assert_no_difference(-> { RubyLLM::ActiveRecord::Model.count }) do
      RubyLLM::ActiveRecord::Model.where(provider: "anthropic").limit(1).update_all(updated_at: 2.minutes.from_now)
      FirefightAi.reload_registry_if_changed!
    end
  end

  test "a call is priced at the provider's own rates, with cache reads at theirs and MiniMax M3's long prompts at its higher tier" do
    # 500k plain input at $1.40, 500k cache reads at $0.26, a million output at $4.40.
    assert_equal 700_000 + 130_000 + 4_400_000, FirefightAi.cost_micros("glm-5.3", provider: "zai", input: 1_000_000, output: 1_000_000, cache_read: 500_000)
    assert_equal 150_000 + 1_200_000, FirefightAi.cost_micros("MiniMax-M3", provider: "minimax", input: 500_000, output: 1_000_000)
    assert_equal 600_000 + 2_400_000, FirefightAi.cost_micros("MiniMax-M3", provider: "minimax", input: 1_000_000, output: 1_000_000)
    assert_equal 2_000_000 + 6_000_000, FirefightAi.cost_micros("qwen3.8-max", provider: "qwen", input: 1_000_000, output: 1_000_000)
  end

  test "the region picks the address, and a region the provider does not serve reaches nothing" do
    zai = FirefightAi::Providers::Zai
    assert_equal "https://api.z.ai/api/paas/v4", zai.address(settings(zai_api_key: "key", zai_region: "global"))
    assert_equal "https://open.bigmodel.cn/api/paas/v4", zai.address(settings(zai_api_key: "key", zai_region: "china"))
    assert_equal "https://api.minimax.cn/v1", FirefightAi::Providers::Minimax.address(settings(minimax_region: "china"))
    assert_not zai.configured?(settings(zai_api_key: "key", zai_region: "mars"))
    assert_not zai.configured?(settings(zai_api_key: "key"))
    assert zai.configured?(settings(zai_api_key: "key", zai_region: "global"))
  end

  test "Qwen reaches QwenCloud and Model Studio in every region, Model Studio's Frankfurt and Tokyo through the workspace's own address" do
    qwen = FirefightAi::Providers::Qwen
    assert_equal "https://eu-central-1.maas.qwencloudapi.com/compatible-mode/v1", qwen.address(settings(qwen_region: "eu-central-1"))
    assert_equal "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", qwen.address(settings(qwen_region: "alibaba-ap-southeast-1"))
    assert_equal "https://llm-4f2a.ap-northeast-1.maas.aliyuncs.com/compatible-mode/v1",
                 qwen.address(settings(qwen_region: "alibaba-ap-northeast-1", qwen_workspace_id: "llm-4f2a"))

    assert_not qwen.configured?(settings(qwen_api_key: "key", qwen_region: "alibaba-eu-central-1")), "Frankfurt needs the workspace"
    assert qwen.configured?(settings(qwen_api_key: "key", qwen_region: "alibaba-eu-central-1", qwen_workspace_id: "llm-4f2a"))
    assert_nil qwen.address(settings(qwen_region: "alibaba-eu-central-1", qwen_workspace_id: "evil.example.com/x")), "a workspace is a plain name"
  end

  test "Z.AI is called with its key, a system message called system, and nothing of OpenAI's prompt cache" do
    answer_with(completion(content: "Checkout is healthy."))

    reply = chat("zai", "glm-5.3", zai_api_key: "zai-key-4f2a", zai_region: "china").with_instructions("You are Halon.").ask("Is checkout down?")

    request = sent_requests.sole
    assert_equal "https://open.bigmodel.cn/api/paas/v4/chat/completions", request[:url]
    assert_equal [ "system", "user" ], request[:body]["messages"].pluck("role")
    assert_not request[:body].key?("prompt_cache_key")
    assert_equal "Checkout is healthy.", reply.content
  end

  test "Z.AI and Qwen are asked for a schema in words and JSON mode, and Qwen stops thinking for it" do
    { [ "zai", "glm-5.3" ] => { zai_api_key: "key", zai_region: "global" }, [ "qwen", "qwen3.8-max" ] => { qwen_api_key: "key", qwen_region: "us-east-1" } }.each do |(slug, model), keys|
      FakeProviderHelper::Adapter.reset!
      answer_with(completion(content: '{"cause":"a bad deploy"}'))

      reply = chat(slug, model, **keys).with_instructions("You are Halon.").with_schema(SCHEMA).ask("Why is checkout down?")

      body = sent_requests.sole[:body]
      assert_equal({ "type" => "json_object" }, body["response_format"])
      assert_equal %w[system system user], body["messages"].pluck("role"), "the schema follows the instructions"
      assert_includes body["messages"].second["content"], '"cause"'
      assert_equal({ "cause" => "a bad deploy" }, reply.parsed)
      slug == "qwen" ? assert_equal(false, body["enable_thinking"]) : assert_not(body.key?("enable_thinking"))
    end
  end

  test "Qwen thinks as it chooses when no JSON is asked for, and is never sent its reasoning back" do
    answer_with(completion(content: nil, reasoning: "Read the logs first.", tool_calls: [ tool_call("call_1", "checkout") ]))
    answer_with(completion(content: "Timeouts in checkout."))

    chat("qwen", "qwen3.8-flash", qwen_api_key: "key", qwen_region: "ap-southeast-1").with_tools(ReadLogs).ask("Is checkout down?")

    assert_not sent_requests.first[:body].key?("enable_thinking")
    assert_not sent_requests.second[:body]["messages"].find { |message| message["role"] == "assistant" }.key?("reasoning_content")
  end

  test "MiniMax splits its reasoning out, and gets it back with the tool call on the next turn, as it asks" do
    answer_with(completion(content: nil, reasoning: "The logs will say whether checkout times out.", tool_calls: [ tool_call("call_1", "checkout") ]))
    answer_with(completion(content: "Checkout timed out three times in the last hour."))

    reply = chat("minimax", "MiniMax-M3.1-Flash", minimax_api_key: "key", minimax_region: "global").with_tools(ReadLogs).ask("Is checkout down?")

    first, second = sent_requests.map { |request| request[:body] }
    assert_equal "https://api.minimax.io/v1/chat/completions", sent_requests.first[:url]
    assert first["reasoning_split"]
    assert_equal "read_logs", first["tools"].sole.dig("function", "name")

    assistant = second["messages"].find { |message| message["role"] == "assistant" }
    assert_equal "The logs will say whether checkout times out.", assistant["reasoning_content"]
    assert_equal "call_1", assistant["tool_calls"].sole["id"]
    assert_equal({ "role" => "tool", "content" => "checkout: 3 timeouts in the last hour", "tool_call_id" => "call_1" },
                 second["messages"].find { |message| message["role"] == "tool" })
    assert_equal "Checkout timed out three times in the last hour.", reply.content
  end

  test "MiniMax is asked for a schema in words alone, and a fenced reply still reads" do
    answer_with(completion(content: "```json\n{\"cause\":\"a bad deploy\"}\n```"))

    reply = chat("minimax", "MiniMax-M3", minimax_api_key: "key", minimax_region: "global").with_schema(SCHEMA).ask("Why is checkout down?")

    body = sent_requests.sole[:body]
    assert_not body.key?("response_format")
    assert_includes body["messages"].first["content"], "JSON Schema"
    assert_equal({ "cause" => "a bad deploy" }, reply.parsed)
  end

  test "MiniMax's refusals in a 200 are raised as what they are, so a spent balance is out of credit and a bad key refused" do
    spent = { id: "x", choices: nil, base_resp: { status_code: 1008, status_msg: "insufficient balance" } }
    error = provider_error("minimax", "MiniMax-M3", status: 200, body: spent, minimax_api_key: "key", minimax_region: "global")
    assert_kind_of RubyLLM::PaymentRequiredError, error
    assert_raises(FirefightAi::OutOfCredit) { FirefightAi.translating_errors { raise error } }

    refused = { base_resp: { status_code: 2049, status_msg: "invalid api key" } }
    assert FirefightAi.key_refused?(provider_error("minimax", "MiniMax-M3", status: 200, body: refused, minimax_api_key: "key", minimax_region: "global"))

    busy = { base_resp: { status_code: 1002, status_msg: "rate limit" } }
    assert FirefightAi.provider_down?(provider_error("minimax", "MiniMax-M3", status: 200, body: busy, minimax_api_key: "key", minimax_region: "global"))
  end

  private

  def settings(**values)
    config = RubyLLM.config.dup
    values.each { |name, value| config.public_send("#{name}=", value) }
    config
  end

  def chat(provider, model, **keys)
    fake_provider_context(**keys).chat(model: model, provider: provider)
  end

  def completion(content:, reasoning: nil, tool_calls: nil)
    message = { role: "assistant", content: content, reasoning_content: reasoning, tool_calls: tool_calls }.compact
    { id: "chatcmpl-1", object: "chat.completion", model: "test", choices: [ { index: 0, message: message, finish_reason: tool_calls ? "tool_calls" : "stop" } ],
      usage: { prompt_tokens: 120, completion_tokens: 30, total_tokens: 150, prompt_tokens_details: { cached_tokens: 0 } },
      base_resp: { status_code: 0, status_msg: "" } }
  end

  def tool_call(id, service)
    { id: id, type: "function", function: { name: "read_logs", arguments: { service: service }.to_json } }
  end
end
