require "test_helper"

module FirefightAi
  class ModelProxyTest < ActiveSupport::TestCase
    # Net::HTTP's streaming shape, enough to hand a request its answer a chunk at a time.
    FakeResponse = Struct.new(:code, :content_type, :chunks) do
      def [](name) = name == "Content-Type" ? content_type : nil
      def read_body(&) = chunks.each(&)
    end

    setup do
      RubyLLM.config.stubs(:anthropic_api_key).returns("sk-firefight")
      RubyLLM.config.stubs(:openai_api_key).returns("sk-openai")
      RubyLLM.config.stubs(:openrouter_api_key).returns("sk-openrouter")
    end

    test "a streamed Anthropic answer passes through as it comes, with Firefight's key, and its usage is read off it" do
      chunks = [
        "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":100,\"cache_read_input_tokens\":40}}}\n\n",
        "event: message_delta\ndata: {\"type\":\"message_delta\",\"usage\":{\"output_tokens\":",
        "25}}\n\n"
      ]
      sent = nil
      answer(FakeResponse.new("200", "text/event-stream", chunks)) { |request| sent = request }

      seen = []
      usage = ModelProxy.new("anthropic").forward(path: "messages", body: { model: "claude-opus-4", max_tokens: 200_000, stream: true }.to_json,
                                                  model: "claude-sonnet-4-5", headers: { "anthropic-version" => "2023-06-01" }) { |*event| seen << event }

      assert_equal [ "sk-firefight", "2023-06-01", nil ], [ sent["x-api-key"], sent["anthropic-version"], sent["Authorization"] ]
      assert_equal({ "model" => "claude-sonnet-4-5", "max_tokens" => ModelProxy::MAX_OUTPUT_TOKENS, "stream" => true }, JSON.parse(sent.body))
      assert_equal [ :start, 200, "text/event-stream" ], seen.first
      assert_equal chunks, seen.drop(1).map(&:last)
      assert_equal ModelProxy::Usage.new(input: 140, output: 25, cache_read: 40, cache_write: 0), usage
    end

    test "an OpenAI answer's usage is read from its last chunk, with the key as a bearer" do
      sent = nil
      answer(FakeResponse.new("200", "text/event-stream", [ "data: {\"choices\":[]}\n\n", "data: {\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":3}}\n\ndata: [DONE]\n\n" ])) { |request| sent = request }

      usage = ModelProxy.new("openai").forward(path: "chat/completions", body: { stream: true, tools: [ { type: "function" } ] }.to_json, model: "gpt-4o") { |*| nil }

      assert_equal "Bearer sk-openai", sent["Authorization"]
      assert_equal({ "include_usage" => true }, JSON.parse(sent.body)["stream_options"])
      assert_equal [ 10, 3 ], [ usage.input, usage.output ]
    end

    test "an answer that is one JSON body is read whole for its usage, however it is laid out" do
      answer(FakeResponse.new("200", "application/json", [ JSON.pretty_generate("usage" => { "prompt_tokens" => 7, "completion_tokens" => 2 }) ])) { |_| nil }

      usage = ModelProxy.new("openai").forward(path: "chat/completions", body: "{}", model: "gpt-4o") { |*| nil }

      assert_equal [ 7, 2 ], [ usage.input, usage.output ]
    end

    test "a refusal for credit is kept so it can be read as one" do
      body = { "type" => "error", "error" => { "type" => "invalid_request_error", "message" => "Your credit balance is too low to access the Anthropic API." } }
      answer(FakeResponse.new("400", "application/json", [ body.to_json ])) { |_| nil }

      proxy = ModelProxy.new("anthropic")
      proxy.forward(path: "messages", body: "{}", model: "claude-sonnet-4-5") { |*| nil }

      assert proxy.refusal.out_of_credit?
    end

    test "a provider's own tools never travel, and a broken stream keeps what it used" do
      Net::HTTP.stubs(:start).raises(Errno::ECONNRESET)
      proxy = ModelProxy.new("anthropic")

      error = assert_raises(ModelProxy::Refused) { proxy.forward(path: "messages", body: { tools: [ { type: "web_search_20250305" } ] }.to_json, model: "x") { |*| nil } }
      assert_match "Only the agent's own tools", error.message
      assert_match "could not be reached", assert_raises(ModelProxy::Refused) { proxy.forward(path: "messages", body: "{}", model: "x") { |*| nil } }.message
      assert_equal ModelProxy::Usage.none, proxy.usage
    end

    test "remote MCP servers and a code execution container named in an Anthropic body never travel" do
      sent = nil
      answer(FakeResponse.new("200", "application/json", [ "{}" ])) { |request| sent = request }

      body = { max_tokens: 100, mcp_servers: [ { type: "url", url: "https://mcp.example.com/sse", name: "outside" } ], container: "container_1" }.to_json
      ModelProxy.new("anthropic").forward(path: "messages", body: body, model: "claude-sonnet-4-5",
                                          headers: { "anthropic-beta" => "mcp-client-2025-04-04" }) { |*| nil }

      assert_equal({ "max_tokens" => 100, "model" => "claude-sonnet-4-5" }, JSON.parse(sent.body))
    end

    test "an OpenRouter call goes to OpenRouter with its key as a bearer, pinned to the session's model alone, and its usage is read" do
      sent = nil
      answer(FakeResponse.new("200", "text/event-stream", [ ": OPENROUTER PROCESSING\n\n", "data: {\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":4}}\n\ndata: [DONE]\n\n" ])) { |request| sent = request }

      body = { stream: true, models: [ "openai/o1-pro" ], route: "fallback", plugins: [ { id: "web" } ] }.to_json
      usage = ModelProxy.new("openrouter").forward(path: "chat/completions", body: body, model: "anthropic/claude-sonnet-4.5") { |*| nil }

      assert_equal "https://openrouter.ai/api/v1/chat/completions", sent.uri.to_s
      assert_equal "Bearer sk-openrouter", sent["Authorization"]
      assert_equal({ "stream" => true, "model" => "anthropic/claude-sonnet-4.5", "stream_options" => { "include_usage" => true } }, JSON.parse(sent.body))
      assert_equal [ 12, 4 ], [ usage.input, usage.output ]
    end

    test "only the paths a coding agent calls, and only providers Firefight can reach, are forwarded" do
      Net::HTTP.expects(:start).never

      assert_raises(ModelProxy::Refused) { ModelProxy.new("anthropic").forward(path: "models", body: "{}", model: "x") { |*| nil } }
      assert_raises(ModelProxy::Refused) { ModelProxy.new("gemini") }
      RubyLLM.config.stubs(:anthropic_api_key).returns(nil)
      assert_raises(ModelProxy::Refused) { ModelProxy.new("anthropic") }
    end

    test "a workspace's own account forwards with its own key and address, never Firefight's" do
      config = RubyLLM.context do |own|
        own.anthropic_api_key = "sk-workspace"
        own.anthropic_api_base = "https://llm.example.com/v1"
      end.config
      sent = nil
      Net::HTTP.expects(:start).with("llm.example.com", 443, has_entries(use_ssl: true)).yields(fake_http { |request| sent = request })

      ModelProxy.new("anthropic", config: config).forward(path: "messages", body: "{}", model: "claude-sonnet-4-5") { |*| nil }

      assert_equal [ "sk-workspace", "/v1/messages" ], [ sent["x-api-key"], sent.path ]
    end

    private

    def answer(response, &seen)
      Net::HTTP.stubs(:start).yields(fake_http(response, &seen))
    end

    def fake_http(response = FakeResponse.new("200", "application/json", [ "{}" ]), &seen)
      http = Object.new
      http.define_singleton_method(:request) do |request, &block|
        seen.call(request)
        block.call(response)
      end
      http
    end
  end
end
