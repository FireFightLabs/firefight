module FirefightAi
  module Providers
    # MiniMax's OpenAI compatible API, at api.minimax.io, and its China platform at api.minimax.cn, where a key made on
    # one does not work on the other (platform.minimax.io/docs/api-reference/text-openai-api and the same page on
    # platform.minimax.cn). Its subscription plans are for coding tools, so only pay-as-you-go keys are offered.
    #
    # Its models think before they answer, and MiniMax-M3.1-Flash always does. reasoning_split puts the thinking in
    # reasoning_content, and the next turn sends it back, which MiniMax asks for so a model carries on between tool calls.
    # It has no JSON mode, so a schema is asked for in words alone.
    #
    # MiniMax answers some refusals with a 200 whose base_resp says what went wrong
    # (platform.minimax.io/docs/api-reference/text-chat-openai, errorcode), so those are raised as the refusal they are.
    class Minimax < Regional
      # base_resp.status_code, from MiniMax's error codes, to the RubyLLM class that refusal is everywhere else.
      REFUSALS = {
        1002 => RubyLLM::RateLimitError, 1039 => RubyLLM::RateLimitError, 1041 => RubyLLM::RateLimitError,
        2045 => RubyLLM::RateLimitError, 2046 => RubyLLM::RateLimitError, 2047 => RubyLLM::RateLimitError,
        1004 => RubyLLM::UnauthorizedError, 2049 => RubyLLM::UnauthorizedError,
        1008 => RubyLLM::PaymentRequiredError, 2053 => RubyLLM::PaymentRequiredError,
        1000 => RubyLLM::ServerError, 1024 => RubyLLM::ServerError, 1033 => RubyLLM::ServerError,
        1001 => RubyLLM::ServiceUnavailableError, 2066 => RubyLLM::ServiceUnavailableError, 2064 => RubyLLM::OverloadedError
      }.freeze

      class ChatCompletions < RubyLLM::Protocols::ChatCompletions
        include Dialect

        def render_payload(...)
          payload = super
          payload[:reasoning_split] = true
          payload
        end

        def json_mode? = false

        def parse_completion_body(data, raw:)
          Minimax.refuse!(data, raw)
          super
        end
      end

      protocol :chat_completions, ChatCompletions

      class << self
        def addresses = { "global" => "https://api.minimax.io/v1", "china" => "https://api.minimax.cn/v1" }

        def display_name = "MiniMax"

        def configuration_options = %i[minimax_api_key minimax_region]

        def configuration_requirements = %i[minimax_api_key minimax_region]

        def refuse!(data, raw)
          status = data.is_a?(Hash) ? data.dig("base_resp", "status_code").to_i : 0
          return if status.zero?

          message = "#{data.dig('base_resp', 'status_msg').presence || 'MiniMax refused the call'} (#{status})"
          raise REFUSALS.fetch(status, RubyLLM::BadRequestError).new(message, response: raw)
        end
      end

      # A refusal with an HTTP status says what went wrong in base_resp too.
      def parse_error(response)
        body = parse_error_body(response)
        message = body.dig("base_resp", "status_msg") if body.is_a?(Hash)
        message.presence || super
      end
    end
  end
end
