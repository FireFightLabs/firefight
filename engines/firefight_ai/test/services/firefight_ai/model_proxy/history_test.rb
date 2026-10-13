require "test_helper"

module FirefightAi
  class ModelProxy
    class HistoryTest < ActiveSupport::TestCase
      BIG = "x" * 30_000

      test "nothing is cleared until the oldest results behind the last few add up to a batch worth breaking the cache for" do
        small = chat_session(reads: 8, output: "y" * 100)
        assert_equal 0, History.new(small, wire: History::CHAT_COMPLETIONS).clear_through(0)

        few = chat_session(reads: History::KEEP_RECENT, output: BIG)
        assert_equal 0, History.new(few, wire: History::CHAT_COMPLETIONS).clear_through(0), "the last few results are never cleared"

        long = chat_session(reads: 9, output: BIG)
        assert_equal 4, History.new(long, wire: History::CHAT_COMPLETIONS).clear_through(0)
      end

      test "a cleared batch stays as it is call after call until the next one, so the start of the session reads the same" do
        first = chat_session(reads: 9, output: BIG)
        history = History.new(first, wire: History::CHAT_COMPLETIONS)
        count = history.clear_through(0)
        history.apply!(count, server: false)

        following = chat_session(reads: 10, output: BIG)
        later = History.new(following, wire: History::CHAT_COMPLETIONS)
        assert_equal history.conversation, later.conversation
        assert_equal count, later.clear_through(count), "one more result is not a batch"
        later.apply!(count, server: false)

        assert_equal first["messages"].first(2 + (count * 2)), following["messages"].first(2 + (count * 2))
        assert_equal 9, History.new(chat_session(reads: 14, output: BIG), wire: History::CHAT_COMPLETIONS).clear_through(count)
      end

      test "a cleared result says what it was and how to read it again, and the person's answers are never cleared" do
        body = chat_session(reads: 9, output: BIG, asked_at: 1)
        history = History.new(body, wire: History::CHAT_COMPLETIONS, kept_tools: %w[wait_for_answer])
        history.apply!(history.clear_through(0), server: false)

        results = body["messages"].select { |message| message["role"] == "tool" }
        assert_equal format(History::STUB, what: "read src/file_0.rb"), results.first["content"]
        assert_equal BIG, results.second["content"], "the answer stays"
        assert_equal BIG, results.last["content"]
      end

      test "a fresh conversation, such as a change sent back after its review, has its own key and starts from nothing" do
        one = History.new(chat_session(reads: 9, output: BIG), wire: History::CHAT_COMPLETIONS)
        other = History.new(chat_session(reads: 9, output: BIG, brief: "Correct it"), wire: History::CHAT_COMPLETIONS)

        assert_not_equal one.conversation, other.conversation
      end

      test "a count kept from a longer history never clears the last few" do
        assert_equal 1, History.new(chat_session(reads: 6, output: BIG), wire: History::CHAT_COMPLETIONS).clear_through(50)
      end

      test "Anthropic's format asks the provider to clear exactly the batch, and is never edited here" do
        body = message_session(reads: 9, output: BIG)
        before = body.deep_dup
        history = History.new(body, wire: History::MESSAGES, kept_tools: %w[wait_for_answer])
        count = history.clear_through(0)

        assert history.apply!(count, server: true)
        assert_equal before["messages"], body["messages"]
        edit = body.dig("context_management", "edits").sole
        assert_equal({ "type" => History::SERVER_EDIT, "trigger" => { "type" => "tool_uses", "value" => 1 }, "keep" => { "type" => "tool_uses", "value" => 9 - count },
                       "clear_at_least" => { "type" => "input_tokens", "value" => History::CLEAR_AT_LEAST }, "exclude_tools" => [ "firefight_wait_for_answer" ] }, edit)

        untouched = message_session(reads: 9, output: BIG)
        assert_not History.new(untouched, wire: History::MESSAGES).apply!(count, server: false)
        assert_nil untouched["context_management"], "a provider that refused to clear is left whole"
      end

      test "OpenAI's responses format has its function outputs cleared" do
        input = [ { "role" => "user", "content" => "Fix it" } ]
        9.times do |index|
          input << { "type" => "function_call", "call_id" => "call_#{index}", "name" => "bash", "arguments" => { command: "cat file_#{index}" }.to_json }
          input << { "type" => "function_call_output", "call_id" => "call_#{index}", "output" => BIG }
        end
        body = { "instructions" => "You write code.", "input" => input }
        history = History.new(body, wire: History::RESPONSES)
        history.apply!(history.clear_through(0), server: false)

        assert_equal format(History::STUB, what: "bash cat file_0"), input.third["output"]
        assert_equal BIG, input.last["output"]
      end

      private

      def chat_session(reads:, output:, brief: "Fix it", asked_at: nil)
        messages = [ { "role" => "system", "content" => "You write code." }, { "role" => "user", "content" => brief } ]
        reads.times do |index|
          name = index == asked_at ? "firefight_wait_for_answer" : "read"
          messages << { "role" => "assistant", "tool_calls" => [ { "id" => "call_#{index}", "type" => "function",
                                                                   "function" => { "name" => name, "arguments" => { filePath: "src/file_#{index}.rb" }.to_json } } ] }
          messages << { "role" => "tool", "tool_call_id" => "call_#{index}", "content" => output }
        end
        { "model" => "a-model", "messages" => messages }
      end

      def message_session(reads:, output:)
        messages = [ { "role" => "user", "content" => [ { "type" => "text", "text" => "Fix it" } ] } ]
        reads.times do |index|
          messages << { "role" => "assistant", "content" => [ { "type" => "tool_use", "id" => "toolu_#{index}", "name" => "read", "input" => { "filePath" => "f#{index}" } } ] }
          messages << { "role" => "user", "content" => [ { "type" => "tool_result", "tool_use_id" => "toolu_#{index}", "content" => output } ] }
        end
        { "system" => "You write code.", "messages" => messages, "tools" => [ { "name" => "read" }, { "name" => "firefight_wait_for_answer" } ] }
      end
    end
  end
end
