module FirefightAi
  class ModelProxy
    # The tools a model's answer calls, read off the answer as it streams by, so what each call was for can be told
    # from them, and what the provider says it cleared from the request. Reads each provider's own shapes, a whole
    # answer or the events of a stream, and keeps only a call's name and arguments.
    class Calls
      Call = Data.define(:name, :input)

      # What the provider said it cleared, as Anthropic's context editing reports it, summed over its edits.
      Cleared = Data.define(:tool_uses, :input_tokens)

      attr_reader :cleared

      def initialize
        @calls = {}
        @arguments = Hash.new { |hash, key| hash[key] = +"" }
      end

      def read(object)
        return unless object.is_a?(Hash)

        read_cleared(object["context_management"] || object.dig("delta", "context_management"))
        read_messages(object)
        read_chat(object)
        read_responses(object)
      end

      def to_a
        @calls.map { |key, (name, input)| Call.new(name: name, input: input || parsed(@arguments[key])) }
      end

      private

      # Anthropic's format sends tool_use blocks whole, or starts one and fills it in with input_json_delta.
      def read_messages(object)
        Array(object["content"]).each_with_index { |block, index| take_block("content-#{index}", block) }
        take_block("block-#{object['index']}", object["content_block"]) if object["type"] == "content_block_start"
        delta = object["delta"]
        @arguments["block-#{object['index']}"] << delta["partial_json"].to_s if object["type"] == "content_block_delta" && delta.is_a?(Hash) && delta["type"] == "input_json_delta"
      end

      def take_block(key, block)
        return unless block.is_a?(Hash) && block["type"] == "tool_use"

        filled = block["input"].is_a?(Hash) && block["input"].any?
        @calls[key] = [ block["name"].to_s, (block["input"] if filled) ]
      end

      # OpenAI's chat completions, as OpenRouter speaks them too, carry tool_calls whole in a message or a piece at a time.
      def read_chat(object)
        Array(object["choices"]).each_with_index do |choice, at|
          next unless choice.is_a?(Hash)

          whole = choice.dig("message", "tool_calls")
          Array(whole).each_with_index { |call, index| take_function("message-#{at}-#{index}", call["function"], whole: true) if call.is_a?(Hash) }
          Array(choice.dig("delta", "tool_calls")).each do |call|
            take_function("delta-#{at}-#{call['index']}", call["function"], whole: false) if call.is_a?(Hash)
          end
        end
      end

      def take_function(key, function, whole:)
        return unless function.is_a?(Hash)

        name = function["name"].to_s
        @calls[key] = [ name, nil ] if name.present? || whole
        @arguments[key] << function["arguments"].to_s
      end

      # OpenAI's responses carry function_call items, whole in the answer or once each is done in a stream.
      def read_responses(object)
        items = Array(object["output"])
        items << object["item"] if object["type"] == "response.output_item.done"
        items.each do |item|
          next unless item.is_a?(Hash) && item["type"] == "function_call"

          @calls["item-#{item['call_id'] || item['id']}"] = [ item["name"].to_s, parsed(item["arguments"]) ]
        end
      end

      def read_cleared(managed)
        edits = Array(managed.is_a?(Hash) ? managed["applied_edits"] : nil).grep(Hash)
        return if edits.empty?

        @cleared = Cleared.new(tool_uses: edits.sum { |edit| edit["cleared_tool_uses"].to_i }, input_tokens: edits.sum { |edit| edit["cleared_input_tokens"].to_i })
      end

      def parsed(text)
        value = text.is_a?(String) ? JSON.parse(text.presence || "{}") : text
        value.is_a?(Hash) ? value : {}
      rescue JSON::ParserError
        {}
      end
    end
  end
end
