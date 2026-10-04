require "test_helper"

module Integrations
  class CodingAgentApiTest < ActiveSupport::TestCase
    test "Devin is reached under the organization with the key as a bearer token, and a session is created with its body" do
      Http.expects(:request).with do |uri, request, **|
        uri.to_s == "https://api.devin.ai/v3/organizations/org-abc/sessions" && request.is_a?(Net::HTTP::Post) &&
          request["Authorization"] == "Bearer cog_key" && JSON.parse(request.body) == { "prompt" => "Fix it", "max_acu_limit" => 5 }
      end.returns(response(200, { session_id: "devin-1", url: "https://app.devin.ai/sessions/1" }))

      answer = DevinApi.new("cog_key", "org-abc").create_session("prompt" => "Fix it", "max_acu_limit" => 5)

      assert_equal "devin-1", answer["session_id"]
    end

    test "Devin's messages are read a page at a time, and a session is terminated with DELETE" do
      Http.expects(:request).with { |uri, request, **| uri.path == "/v3/organizations/org-abc/sessions/devin-1/messages" && uri.query == "first=200&after=c2" && request.is_a?(Net::HTTP::Get) }
          .returns(response(200, { items: [] }))
      Http.expects(:request).with { |uri, request, **| uri.path == "/v3/organizations/org-abc/sessions/devin-1" && request.is_a?(Net::HTTP::Delete) }
          .returns(response(200, {}))

      api = DevinApi.new("cog_key", "org-abc")
      api.messages("devin-1", after: "c2")
      api.terminate("devin-1")
    end

    test "Devin's problem detail is its refusal, and a 429 is its own error" do
      Http.stubs(:request).returns(response(403, { title: "Forbidden", status: 403, detail: "Missing permission UseDevinSessions" }))

      error = assert_raises(DevinApi::Error) { DevinApi.new("cog_key", "org-abc").whoami }

      assert_equal [ "Devin answered 403: Missing permission UseDevinSessions", 403 ], [ error.message, error.status ]
      Http.stubs(:request).returns(response(429, { title: "Too Many Requests", status: 429 }))
      assert_raises(CodingAgentApi::RateLimited) { DevinApi.new("cog_key", "org-abc").whoami }
    end

    test "Cursor creates an agent, reads and cancels its run, and says its own error message" do
      Http.expects(:request).with do |uri, request, **|
        uri.to_s == "https://api.cursor.com/v1/agents" && request["Authorization"] == "Bearer crsr_key" && JSON.parse(request.body)["autoCreatePR"] == true
      end.returns(response(200, { agent: { id: "bc-1" }, run: { id: "run-1" } }))
      Http.expects(:request).with { |uri, request, **| uri.path == "/v1/agents/bc-1/runs/run-1/cancel" && request.is_a?(Net::HTTP::Post) }.returns(response(200, { id: "run-1" }))

      api = CursorApi.new("crsr_key")
      assert_equal "bc-1", api.create_agent("prompt" => { "text" => "Fix it" }, "autoCreatePR" => true).dig("agent", "id")
      api.cancel("bc-1", "run-1")

      Http.stubs(:request).returns(response(400, { error: { code: "integration_not_connected", message: "Connect GitHub in Cursor first" } }))
      assert_equal "Cursor answered 400: Connect GitHub in Cursor first", assert_raises(CursorApi::Error) { api.me }.message
    end

    test "Factory finds a computer by name, sends a message and reads the Droid's messages" do
      Http.expects(:request).with { |uri, **| uri.to_s == "https://api.factory.ai/api/v0/computers/name/my%20box" }.returns(response(200, { id: "c1" }))
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/api/v0/sessions/s1/messages" && request.is_a?(Net::HTTP::Post) && JSON.parse(request.body) == { "text" => "Fix it" }
      end.returns(response(200, { messageId: "m1", status: "pending" }))
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/api/v0/sessions/s1/messages" && request.is_a?(Net::HTTP::Get) && URI.decode_www_form(uri.query).to_h == { "role" => "assistant", "limit" => "100", "cursor" => "n2" }
      end.returns(response(200, { messages: [], pagination: { hasMore: false, nextCursor: nil } }))

      api = FactoryApi.new("fk_key")
      assert_equal "c1", api.computer_named("my box")["id"]
      api.send_message("s1", "Fix it")
      api.messages("s1", cursor: "n2")

      Http.stubs(:request).returns(response(403, { detail: "Sessions are not enabled", status: 403, title: "Forbidden" }))
      assert_equal "Factory answered 403: Sessions are not enabled", assert_raises(FactoryApi::Error) { api.session("s1") }.message
    end

    test "an EU Factory connection reaches Factory's EU deployment, and one that names none the Global one" do
      Http.expects(:request).with { |uri, **| uri.to_s == "https://api.eu.factory.ai/api/v0/sessions/s1" }.returns(response(200, { sessionId: "s1" }))
      Http.expects(:request).with { |uri, **| uri.to_s == "https://api.factory.ai/api/v0/sessions/s1" }.returns(response(200, { sessionId: "s1" }))

      FactoryApi.new("fk_key", "eu").session("s1")
      FactoryApi.new("fk_key").session("s1")
    end

    test "a change that went through answered with something that is not JSON is still one that went through" do
      Http.stubs(:request).returns(stub(code: "200", body: "OK"))

      assert_equal({}, FactoryApi.new("fk_key").interrupt("s1"))
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
