require "test_helper"

module Integrations
  class NativePackTest < ActiveSupport::TestCase
    fixtures :workspaces, :users, :workspace_memberships

    class FakePack < NativePack
      tool :echo_text, description: "Echoes text back",
                       params_schema: { "type" => "object", "properties" => { "text" => { "type" => "string" } } },
                       read_only: true
      tool :write_thing, description: "Writes a thing", params_schema: { "type" => "object" }, read_only: false

      def echo_text(environment_row:, arguments:)
        "echo: #{arguments['text']}"
      end

      def write_thing(environment_row:, arguments:)
        { "content" => [ { "type" => "text", "text" => "written" } ] }
      end
    end

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
      assert_equal [ "echo_text", "write_thing" ], FakePack.tool_definitions.map(&:name)
      assert_equal [ "other_tool" ], OtherPack.tool_definitions.map(&:name)

      echo = FakePack.tool_definitions.first
      assert echo.read_only
      assert_equal "Echoes text back", echo.description
    end

    test "call dispatches to the tool method with row and arguments" do
      result = FakePack.new(@integration).call("echo_text", environment_row: nil, arguments: { "text" => "hi" })
      assert_equal "echo: hi", result
    end

    test "call raises on a tool the pack does not declare" do
      error = assert_raises(NativePack::Error) do
        FakePack.new(@integration).call("missing", environment_row: nil, arguments: {})
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
      assert_nil FakePack.new(@integration).check_health!(nil)
    end
  end
end
