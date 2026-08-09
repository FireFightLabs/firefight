require "test_helper"

module Integrations
  class NativeExecutorTest < ActiveSupport::TestCase
    fixtures :workspaces, :users, :workspace_memberships

    class EchoPack < NativePack
      tool :echo_text, description: "Echoes", params_schema: {}, read_only: true
      tool :structured, description: "Already MCP-shaped", params_schema: {}, read_only: true
      tool :data_result, description: "Returns a hash", params_schema: {}, read_only: true

      def echo_text(environment_row:, arguments:)
        "echo: #{arguments['text']}"
      end

      def structured(environment_row:, arguments:)
        { "content" => [ { "type" => "text", "text" => "as-is" } ], "isError" => false }
      end

      def data_result(environment_row:, arguments:)
        { "rows" => [ 1, 2 ] }
      end
    end

    setup do
      @integration = Integration.create!(
        workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE,
        provider: "fake", name: "Fake"
      )
      @integration.tools.create!(name: "echo_text", read_only: true, enabled: true)
      NativePacks.stubs(:for).with("fake").returns(EchoPack)
    end

    test "call dispatches through the pack and wraps plain results in MCP content shape" do
      tool = @integration.tools.find_by!(name: "echo_text")
      result = NativeExecutor.call(tool: tool, environment_row: nil, arguments: { "text" => "hi" })

      assert_equal [ { "type" => "text", "text" => "echo: hi" } ], result["content"]
    end

    test "MCP-shaped results pass through untouched" do
      tool = @integration.tools.create!(name: "structured", read_only: true, enabled: true)
      result = NativeExecutor.call(tool: tool, environment_row: nil, arguments: {})

      assert_equal "as-is", result["content"].first["text"]
      assert_equal false, result["isError"]
    end

    test "hash results serialize as pretty JSON text" do
      tool = @integration.tools.create!(name: "data_result", read_only: true, enabled: true)
      result = NativeExecutor.call(tool: tool, environment_row: nil, arguments: {})

      assert_includes result["content"].first["text"], "\"rows\""
    end

    test "a provider without a registered pack raises" do
      NativePacks.unstub(:for)
      tool = @integration.tools.find_by!(name: "echo_text")

      assert_raises(NativePack::Error) do
        NativeExecutor.call(tool: tool, environment_row: nil, arguments: {})
      end
    end

    test "Executor.for selects by kind and rejects unimplemented kinds" do
      assert_equal NativeExecutor, Executor.for(@integration)

      mcp = Integration.new(kind: Integration::KIND_MCP)
      assert_equal McpExecutor, Executor.for(mcp)

      http = Integration.new(kind: Integration::KIND_HTTP)
      assert_raises(NativePack::Error) { Executor.for(http) }
    end
  end
end
