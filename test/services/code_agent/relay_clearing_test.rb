require "test_helper"

# A coding agent resends its whole session on every call. The relay clears the oldest tool results in batches, keeps
# how many each conversation cleared on the session so the next call clears the same ones, and the ledger says what
# each call was for.
class CodeAgent::RelayClearingTest < ActiveSupport::TestCase
  Answer = Struct.new(:code, :content_type, :chunks) do
    def [](name) = name == "Content-Type" ? content_type : nil
    def read_body(&) = chunks.each(&)
  end

  setup do
    @workspace = workspaces(:slack_workspace_one)
    RubyLLM.config.stubs(:openrouter_api_key).returns("sk-openrouter")
    @session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "z-ai/glm-5.3", provider: "openrouter"),
                                       repository: "acme/api")
    @sent = []
  end

  test "a batch of old results is cleared and kept on the session, so the next call of the conversation clears the same ones" do
    answer_with({ choices: [ { delta: { tool_calls: [ { index: 0, id: "call_x", function: { name: "bash", arguments: { command: "rg needle app" }.to_json } } ] } } ] })

    relay(session_with(reads: 9))
    first = @sent.last
    cleared = first["messages"].select { |message| message["role"] == "tool" }.count { |message| message["content"].start_with?("[Firefight cleared") }
    assert_equal 4, cleared
    assert_equal [ 4 ], @session.reload.cleared_through.values

    relay(session_with(reads: 10))
    assert_equal first["messages"], @sent.last["messages"].first(first["messages"].size), "the session reads the same up to where it grew"

    inference = Inference.where(inferable: @session).order(:created_at).last
    assert_equal({ "kinds" => [ CodeAgent::CallKind::SEARCH ], "tools" => [ "bash" ], "cleared" => 4, "clearedByProvider" => false,
                   "providerRefusedClearing" => false }, inference.agent_call.except("conversation"))
  end

  test "a count only ever grows, so of two calls at once the larger stands" do
    trim = FirefightAi::ModelProxy::Trim.new(conversation: "abc", count: 6, by_provider: false, provider_refused: false)
    @session.cleared!(trim)
    @session.cleared!(trim.with(count: 4))
    @session.cleared!(trim.with(conversation: "def", count: 2))

    assert_equal({ "abc" => 6, "def" => 2 }, @session.reload.cleared_through)
    assert @session.provider_clears?

    @session.cleared!(trim.with(count: 0, provider_refused: true))
    assert_not @session.reload.provider_clears?
    assert_equal({ "abc" => 6, "def" => 2 }, @session.cleared_through)
  end

  test "what the change spent is read from the ledger by feature" do
    answer_with({ usage: { prompt_tokens: 100, completion_tokens: 10, prompt_tokens_details: { cached_tokens: 80 } } })
    relay(session_with(reads: 1))
    relay(session_with(reads: 2))

    spend = @session.spend.fetch(CodeAgentSession::FEATURE)
    assert_equal [ 2, 200, 160, 20 ], spend.values_at(:calls, :input_tokens, :cache_read_tokens, :output_tokens)
  end

  private

  def relay(body)
    CodeAgent::Relay.new(@session.reload).forward(path: "chat/completions", body: body.to_json, headers: {}) { |*| nil }
  end

  def answer_with(object)
    sent = @sent
    http = Object.new
    http.define_singleton_method(:request) do |request, &block|
      sent << JSON.parse(request.body)
      block.call(Answer.new("200", "text/event-stream", [ "data: #{object.to_json}\n\n" ]))
    end
    Net::HTTP.stubs(:start).yields(http)
  end

  def session_with(reads:)
    messages = [ { role: "system", content: "You write code." }, { role: "user", content: "Fix it" } ]
    reads.times do |index|
      messages << { role: "assistant", tool_calls: [ { id: "call_#{index}", type: "function", function: { name: "read", arguments: { filePath: "f#{index}" }.to_json } } ] }
      messages << { role: "tool", tool_call_id: "call_#{index}", content: "x" * 30_000 }
    end
    { stream: true, messages: messages }
  end
end
