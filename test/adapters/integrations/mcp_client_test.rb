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
  end
end
