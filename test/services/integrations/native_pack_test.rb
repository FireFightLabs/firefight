require "test_helper"

module Integrations
  class NativePackTest < ActiveSupport::TestCase
    fixtures :workspaces, :users, :workspace_memberships

    class OtherPack < NativePack
      tool :other_tool, description: "Elsewhere", params_schema: {}, read_only: true

      def other_tool(environment_row:, arguments:)
        "other"
      end
    end

    setup do
      @integration = Integration.create!(
        workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE,
        provider: "fake", name: "Fake Pack"
      )
    end

    test "subclasses declare tools independently" do
      assert_equal [ "echo_text", "structured", "data_result", "write_thing" ],
                   FakeNativePack.tool_definitions.map(&:name)
      assert_equal [ "other_tool" ], OtherPack.tool_definitions.map(&:name)

      echo = FakeNativePack.tool_definitions.first
      assert echo.read_only
      assert_equal "Echoes text back", echo.description
      assert_equal({}, echo.spec, "pack tools carry no execution spec; the method name is the dispatch")
    end

    test "call dispatches to the tool method with row and arguments" do
      result = FakeNativePack.new(@integration).call("echo_text", environment_row: nil, arguments: { "text" => "hi" })
      assert_equal "echo: hi", result
    end

    test "call raises on a tool the pack does not declare" do
      error = assert_raises(NativePack::Error) do
        FakeNativePack.new(@integration).call("missing", environment_row: nil, arguments: {})
      end
      assert_match(/Unknown tool 'missing'/, error.message)
    end

    test "tool names must be valid method names" do
      assert_raises(ArgumentError) do
        Class.new(NativePack) do
          tool "logs.query", description: "Dots break dispatch", params_schema: {}, read_only: true
        end
      end
    end

    test "default health check accepts" do
      assert_nil FakeNativePack.new(@integration).check_health!(nil)
    end

    test "pack errors rescue as Integrations::Error" do
      assert_operator NativePack::Error, :<, Integrations::Error
      assert_operator McpClient::Error, :<, Integrations::Error
    end
  end
end
