module FirefightAi
  class ModelProxy
    # A coding agent sends its whole session on every call, so a file it read early rides along on every call after it,
    # read from the provider's cache each time. Once the oldest tool results behind the last few calls add up to enough,
    # they are cleared in one batch and stay cleared, so the start of the session reads the same from call to call and
    # the provider's cache keeps working between batches. A provider that clears them itself (Anthropic's context
    # editing) is asked to clear exactly that many, since it checks the agent's earlier reasoning against the session as
    # it was sent, and an edit made here would break that. Elsewhere each is replaced here with a line saying what it
    # was and that the tool can be run again. The caller keeps how many each conversation has cleared between calls,
    # under the conversation's key.
    class History
      MESSAGES = "messages".freeze
      CHAT_COMPLETIONS = "chat/completions".freeze
      RESPONSES = "responses".freeze

      # The last few results are what the agent is working from, so they are never cleared.
      KEEP_RECENT = 5
      # A batch clears at least this much and this share of the request, so the cache it breaks is worth breaking.
      MIN_CLEAR_TOKENS = 20_000
      MIN_CLEAR_SHARE = 0.25
      CHARACTERS_PER_TOKEN = 4
      # The provider skips a clear that would free less, measured in its own tokens.
      CLEAR_AT_LEAST = 10_000
      SERVER_EDIT = "clear_tool_uses_20250919".freeze
      SERVER_BETA = "context-management-2025-06-27".freeze
      STUB = "[Firefight cleared this earlier result to keep the session short. It was the result of %<what>s. Run the tool again if you need it.]".freeze
      DESCRIBED_BY = %w[filePath path command pattern url query name].freeze
      DESCRIBED_LIMIT = 160
      KEY_LENGTH = 16

      Use = Data.define(:id, :name, :input, :size, :result)

      attr_reader :conversation

      # body is the request as parsed JSON, changed in place by apply!. kept_tools names the tools whose results are
      # never cleared, such as the person's answers, by the name the agent knows them by or its suffix.
      def initialize(body, wire:, kept_tools: [])
        @body = body
        @wire = wire
        @kept_tools = kept_tools
        @size = body.to_json.size
        @conversation = Digest::SHA256.hexdigest(opening.to_json)[0, KEY_LENGTH]
      end

      def self.reads?(path) = [ MESSAGES, CHAT_COMPLETIONS, RESPONSES ].include?(path)

      # The tool calls whose results can be cleared, oldest first.
      def uses = @uses ||= read_uses.reject { |use| kept?(use.name) }

      # How many of the oldest results to clear on this call. That is what the conversation already cleared, or the next
      # batch once enough is waiting behind the last few calls, and never so many that fewer than the last few stay.
      def clear_through(already)
        edge = uses.size - KEEP_RECENT
        count = already.to_i.clamp(0, [ edge, 0 ].max)
        return count if edge <= count

        waiting = uses[count...edge].sum(&:size)
        enough = waiting >= MIN_CLEAR_TOKENS * CHARACTERS_PER_TOKEN && waiting >= @size * MIN_CLEAR_SHARE
        enough ? edge : count
      end

      # Clears the oldest count results. Answers true when the provider was asked to clear them, which needs its beta
      # header, and false when nothing was asked of it. A provider that clears for itself is never edited here, so with
      # server false it is left whole.
      def apply!(count, server:)
        return false unless count.positive?

        if @wire == MESSAGES
          return false unless server

          ask_provider(count)
          true
        else
          uses.first(count).each { |use| use.result[result_key] = format(STUB, what: described(use)) }
          false
        end
      end

      private

      def result_key = { CHAT_COMPLETIONS => "content", RESPONSES => "output" }.fetch(@wire)

      # What starts the conversation and never changes in it, so its calls share a key and a fresh one, such as a change
      # sent back after its review, does not.
      def opening
        case @wire
        when MESSAGES then [ @body["system"], Array(@body["messages"]).first ]
        when CHAT_COMPLETIONS then Array(@body["messages"]).take_while { |message| message.is_a?(Hash) && message["role"] != "assistant" }
        else [ @body["instructions"], Array(@body["input"]).take_while { |item| item.is_a?(Hash) && item["type"].to_s.exclude?("function_call") } ]
        end
      end

      def read_uses
        case @wire
        when MESSAGES then message_uses
        when CHAT_COMPLETIONS then chat_uses
        else response_uses
        end
      end

      def message_uses
        blocks = Array(@body["messages"]).select { |message| message.is_a?(Hash) && message["content"].is_a?(Array) }.flat_map { |message| message["content"] }
        results = blocks.select { |block| block.is_a?(Hash) && block["type"] == "tool_result" }.index_by { |block| block["tool_use_id"] }
        blocks.filter_map do |block|
          next unless block.is_a?(Hash) && block["type"] == "tool_use" && results[block["id"]]

          Use.new(id: block["id"], name: block["name"].to_s, input: block["input"], size: results[block["id"]]["content"].to_json.size, result: results[block["id"]])
        end
      end

      def chat_uses
        messages = Array(@body["messages"]).grep(Hash)
        results = messages.select { |message| message["role"] == "tool" }.index_by { |message| message["tool_call_id"] }
        messages.flat_map { |message| Array(message["tool_calls"]) }.filter_map do |call|
          result = call.is_a?(Hash) && results[call["id"]]
          next unless result

          Use.new(id: call["id"], name: call.dig("function", "name").to_s, input: arguments(call.dig("function", "arguments")), size: result["content"].to_json.size,
                  result: result)
        end
      end

      def response_uses
        items = Array(@body["input"]).grep(Hash)
        results = items.select { |item| item["type"] == "function_call_output" }.index_by { |item| item["call_id"] }
        items.filter_map do |item|
          result = item["type"] == "function_call" && results[item["call_id"]]
          next unless result

          Use.new(id: item["call_id"], name: item["name"].to_s, input: arguments(item["arguments"]), size: result["output"].to_json.size, result: result)
        end
      end

      def arguments(text)
        parsed = text.is_a?(String) ? JSON.parse(text) : text
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      def kept?(name) = @kept_tools.any? { |kept| name == kept || name.end_with?("_#{kept}") }

      # Asks for exactly the oldest count to be cleared, by keeping the rest, so the same count clears the same results
      # on every call until the next batch.
      def ask_provider(count)
        edit = { "type" => SERVER_EDIT, "trigger" => { "type" => "tool_uses", "value" => 1 },
                 "keep" => { "type" => "tool_uses", "value" => uses.size - count },
                 "clear_at_least" => { "type" => "input_tokens", "value" => CLEAR_AT_LEAST } }
        excluded = Array(@body["tools"]).filter_map { |tool| tool["name"] if tool.is_a?(Hash) && kept?(tool["name"].to_s) }
        edit["exclude_tools"] = excluded if excluded.any?
        managed = @body["context_management"].is_a?(Hash) ? @body["context_management"] : {}
        edits = Array(managed["edits"]).reject { |each| each.is_a?(Hash) && each["type"] == SERVER_EDIT }
        @body["context_management"] = managed.merge("edits" => edits + [ edit ])
      end

      def described(use)
        input = use.input.is_a?(Hash) ? use.input : {}
        detail = DESCRIBED_BY.lazy.map { |key| input[key] }.find { |value| value.is_a?(String) && value.present? }
        [ use.name, detail.to_s.squish.truncate(DESCRIBED_LIMIT).presence ].compact.join(" ")
      end
    end
  end
end
