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
      # the session id captured from initialize is used by the http layer via @session_id
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

    test "surfaces a non-2xx HTTP status" do
      resp = stub(code: "401", body: "unauthorized")
      resp.stubs(:[]).returns(nil)
      @client.stubs(:post).returns(resp)

      error = assert_raises(McpClient::Error) { @client.ping }
      assert_match(/HTTP 401/, error.message)
    end
  end
end
