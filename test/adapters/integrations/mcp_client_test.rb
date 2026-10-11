require "test_helper"

module Integrations
  class McpClientTest < ActiveSupport::TestCase
    setup do
      @client = McpClient.new(server_url: "https://mcp.example/mcp", headers: { "Authorization" => "Bearer x" })
    end

    test "carries the session id from initialize onto later requests" do
      init = stub(code: "200", body: { jsonrpc: "2.0", id: 1, result: { protocolVersion: "2025-06-18" } }.to_json)
      init.stubs(:[]).with("Content-Type").returns("application/json")
      init.stubs(:[]).with("Mcp-Session-Id").returns("sess-123")

      initialized = stub(code: "202", body: "")
      initialized.stubs(:[]).returns(nil)

      list_req = nil
      list = stub(code: "200", body: { jsonrpc: "2.0", id: 3, result: { tools: [ { "name" => "pr.list" } ] } }.to_json)
      list.stubs(:[]).with("Content-Type").returns("application/json")
      list.stubs(:[]).with("Mcp-Session-Id").returns(nil)

      call = 0
      @client.stubs(:post).with do |payload|
        call += 1
        list_req = payload if payload[:method] == "tools/list"
        true
      end.returns(init, initialized, list)

      tools = @client.tools_list

      assert_equal [ { "name" => "pr.list" } ], tools
      assert_equal 3, call, "initialize, initialized notification, then tools/list"
      assert_equal "sess-123", @client.instance_variable_get(:@session_id)
    end

    test "a call given a time limit spends it across the handshake and the call, and stops once it runs out" do
      client = McpClient.new(server_url: "https://mcp.example/mcp", within: 15)
      client.stubs(:now).returns(100.0, 104.0, 112.0, 116.0)
      waits = []
      Http.stubs(:request).with { |_uri, _request, read_timeout:, **| waits << read_timeout }.returns(answer(id: 1, result: {}), notified)

      error = assert_raises(McpClient::Error) { client.call_tool(name: "execute_read_query", arguments: {}) }

      assert_equal [ 11.0, 3.0 ], waits, "the handshake waits what is left of 15 seconds, and so does the notification after it"
      assert_kind_of Integrations::TimedOut, error
      assert_equal "mcp.example did not answer within 15 seconds", error.message
    end

    test "a call with no time limit waits the usual time on each request" do
      waits = []
      Http.stubs(:request).with { |_uri, _request, read_timeout:, **| waits << read_timeout }
          .returns(answer(id: 1, result: {}), notified, answer(id: 2, result: { "content" => [] }))

      @client.call_tool(name: "execute_read_query", arguments: {})

      assert_equal [ McpClient::READ_TIMEOUT ] * 3, waits
    end

    test "surfaces a JSON-RPC error message" do
      err = stub(code: "200", body: { jsonrpc: "2.0", id: 1, error: { message: "bad token" } }.to_json)
      err.stubs(:[]).with("Content-Type").returns("application/json")
      err.stubs(:[]).with("Mcp-Session-Id").returns(nil)
      @client.stubs(:post).returns(err)

      error = assert_raises(McpClient::Error) { @client.ping }
      assert_match(/bad token/, error.message)
    end

    test "begin_flow always runs PKCE, even for a pre-registered client" do
      OauthClient.stubs(:discover).returns(
        authorization_endpoint: "https://auth.example/authorize",
        token_endpoint: "https://auth.example/token",
        registration_endpoint: nil, scope: nil
      )

      flow = OauthClient.begin_flow(
        server_url: "https://mcp.example/mcp", redirect_uri: "https://ff.example/cb", client_id: "Iv23.abc"
      )

      assert flow[:verifier].present?
      assert_includes flow[:authorize_url], "code_challenge_method=S256"
    end

    test "without an app slug the flow uses the authorize endpoint with PKCE" do
      OauthClient.stubs(:discover).returns(
        authorization_endpoint: "https://auth.example/authorize",
        token_endpoint: "https://auth.example/token", registration_endpoint: nil, scope: "read"
      )

      flow = OauthClient.begin_flow(
        server_url: "https://mcp.example/mcp", redirect_uri: "https://ff.example/cb", client_id: "cid"
      )

      assert_includes flow[:authorize_url], "https://auth.example/authorize?"
      assert_includes flow[:authorize_url], "code_challenge_method=S256"
      assert flow[:verifier].present?
    end

    test "surfaces a non-2xx HTTP status" do
      resp = stub(code: "401", body: "unauthorized")
      resp.stubs(:[]).returns(nil)
      @client.stubs(:post).returns(resp)

      error = assert_raises(McpClient::Error) { @client.ping }
      assert_match(/HTTP 401/, error.message)
    end

    test "every page of a tool list is read, each asked for with the cursor the last one gave" do
      @client.stubs(:ensure_initialized)
      asked = []
      @client.stubs(:request).with do |method, params = {}|
        asked << [ method, params ]
        true
      end.returns({ "tools" => [ { "name" => "getIssue" } ], "nextCursor" => "page-2" }, { "tools" => [ { "name" => "createIssue" } ] })

      assert_equal %w[getIssue createIssue], @client.tools_list.map { |tool| tool["name"] }
      assert_equal [ [ "tools/list", {} ], [ "tools/list", { cursor: "page-2" } ] ], asked
    end

    test "a server that never stops giving a cursor is refused rather than read forever" do
      @client.stubs(:ensure_initialized)
      @client.stubs(:request).returns({ "tools" => [], "nextCursor" => "again" })

      assert_raises(McpClient::Error) { @client.tools_list }
    end

    test "a token is asked for the server itself, without a query that only picks how it answers" do
      OauthClient.stubs(:discover).returns(authorization_endpoint: "https://auth.example/authorize", token_endpoint: "https://auth.example/token",
                                           registration_endpoint: nil, scope: nil)

      flow = OauthClient.begin_flow(server_url: "https://mcp.example/v2/mcp?tools=all", redirect_uri: "https://ff.example/cb", client_id: "abc")

      assert_equal "https://mcp.example/v2/mcp", Rack::Utils.parse_query(URI.parse(flow[:authorize_url]).query)["resource"]
      assert_equal "https://mcp.example/mcp", OauthClient.resource_of("https://mcp.example/mcp")
    end

    test "a region's own OAuth endpoints stand in for the ones its server names, and are enough without them" do
      OauthClient.stubs(:get_json).returns(nil)

      metadata = OauthClient.discover("https://mcp.eu.example/mcp", { authorization_endpoint: "https://eu.example/authorize", token_endpoint: "https://eu.example/token" })

      assert_equal [ "https://eu.example/authorize", "https://eu.example/token" ], metadata.values_at(:authorization_endpoint, :token_endpoint)
      assert_raises(OauthClient::Error) { OauthClient.discover("https://mcp.eu.example/mcp") }
    end

    private

    test "a pasted server on a private network is refused before anything is sent, unless an operator allowed it" do
      client = McpClient.new(server_url: "https://mcp.internal/mcp", checked_for: "custom_mcp")
      PublicAddress.stubs(:resolve).with("mcp.internal").returns(IPAddr.new("10.0.0.5"))
      Http.expects(:request).never

      error = assert_raises(McpClient::Error) { client.ping }
      assert_equal "mcp.internal is on a private network, which Firefight does not connect to.", error.message
      assert_equal "INTEGRATION_CUSTOM_MCP_PRIVATE_HOSTS", PublicAddress.allowed_env("custom_mcp")

      Http.unstub(:request)
      sent = []
      Http.stubs(:request).with { |_uri, _request, ipaddr:, **| sent << ipaddr }.returns(answer(id: 1, result: {}), notified)
      ENV["INTEGRATION_CUSTOM_MCP_PRIVATE_HOSTS"] = "10.0.0.0/8"
      McpClient.new(server_url: "https://mcp.internal/mcp", checked_for: "custom_mcp").ping
      assert_equal [ "10.0.0.5", "10.0.0.5" ], sent, "every request goes to the address checked"
    ensure
      ENV.delete("INTEGRATION_CUSTOM_MCP_PRIVATE_HOSTS")
    end

    test "a public pasted server is reached at the address checked, and a server the registry names is not checked" do
      PublicAddress.stubs(:resolve).with("mcp.acme.example").returns(IPAddr.new("93.184.216.34"))
      sent = []
      Http.stubs(:request).with { |_uri, _request, **options| sent << options[:ipaddr] }.returns(answer(id: 1, result: {}), notified, answer(id: 1, result: {}), notified)

      McpClient.new(server_url: "https://mcp.acme.example/mcp", checked_for: "sentry").ping
      PublicAddress.expects(:check!).never
      McpClient.new(server_url: "https://mcp.sentry.dev/mcp").ping

      assert_equal [ "93.184.216.34", "93.184.216.34", nil, nil ], sent
    end

    def answer(id:, result:)
      response = stub(code: "200", body: { jsonrpc: "2.0", id: id, result: result }.to_json)
      response.stubs(:[]).returns(nil)
      response
    end

    def notified
      response = stub(code: "202", body: "")
      response.stubs(:[]).returns(nil)
      response
    end
  end
end
