require "test_helper"

module FirefightAi
  class ModelProxy
    class CallsTest < ActiveSupport::TestCase
      test "Anthropic's streamed tool calls are read with their arguments as they arrive, and what the provider cleared" do
        calls = Calls.new
        [
          { "type" => "content_block_start", "index" => 0, "content_block" => { "type" => "text", "text" => "" } },
          { "type" => "content_block_start", "index" => 1, "content_block" => { "type" => "tool_use", "id" => "toolu_1", "name" => "bash", "input" => {} } },
          { "type" => "content_block_delta", "index" => 1, "delta" => { "type" => "input_json_delta", "partial_json" => "{\"command\":\"rg " } },
          { "type" => "content_block_delta", "index" => 1, "delta" => { "type" => "input_json_delta", "partial_json" => "foo\"}" } },
          { "type" => "message_delta", "delta" => { "stop_reason" => "tool_use" },
            "context_management" => { "applied_edits" => [ { "type" => "clear_tool_uses_20250919", "cleared_tool_uses" => 4, "cleared_input_tokens" => 21_000 } ] } }
        ].each { |event| calls.read(event) }

        assert_equal [ Calls::Call.new(name: "bash", input: { "command" => "rg foo" }) ], calls.to_a
        assert_equal Calls::Cleared.new(tool_uses: 4, input_tokens: 21_000), calls.cleared
      end

      test "chat completions' tool calls are put together from their pieces, whole or streamed" do
        streamed = Calls.new
        streamed.read({ "choices" => [ { "delta" => { "tool_calls" => [ { "index" => 0, "id" => "call_1", "function" => { "name" => "read", "arguments" => "{\"filePath\":" } } ] } } ] })
        streamed.read({ "choices" => [ { "delta" => { "tool_calls" => [ { "index" => 0, "function" => { "arguments" => "\"a.rb\"}" } } ] } } ] })
        streamed.read({ "choices" => [ { "delta" => { "tool_calls" => [ { "index" => 1, "id" => "call_2", "function" => { "name" => "grep", "arguments" => "{}" } } ] } } ] })

        assert_equal [ [ "read", { "filePath" => "a.rb" } ], [ "grep", {} ] ], streamed.to_a.map { |call| [ call.name, call.input ] }

        whole = Calls.new
        whole.read({ "choices" => [ { "message" => { "tool_calls" => [ { "function" => { "name" => "edit", "arguments" => "{\"filePath\":\"b.rb\"}" } } ] } } ] })
        assert_equal [ Calls::Call.new(name: "edit", input: { "filePath" => "b.rb" }) ], whole.to_a
      end

      test "OpenAI's responses are read from their function call items once, streamed or whole" do
        calls = Calls.new
        item = { "type" => "function_call", "call_id" => "call_9", "name" => "bash", "arguments" => "{\"command\":\"bin/rails test\"}" }
        calls.read({ "type" => "response.output_item.done", "item" => item })
        calls.read({ "output" => [ item ] })

        assert_equal [ Calls::Call.new(name: "bash", input: { "command" => "bin/rails test" }) ], calls.to_a
      end

      test "an answer with no tool calls has none" do
        calls = Calls.new
        calls.read({ "content" => [ { "type" => "text", "text" => "Done." } ] })

        assert_empty calls.to_a
        assert_nil calls.cleared
      end
    end
  end
end
