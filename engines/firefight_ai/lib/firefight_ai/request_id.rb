module FirefightAi
  # The provider's own id for one model call, which its logs and its support find the call by. RubyLLM does not surface
  # it, so it is read off the answer.
  module RequestId
    # The body names it where the answer came whole. Gemini calls it responseId.
    BODY_KEYS = %w[id responseId].freeze
    # A streamed answer leaves no body to read, so the headers name it: OpenRouter's generation id, Anthropic's request
    # id, the request id OpenAI and providers speaking its format send, and Bedrock's.
    HEADERS = %w[x-generation-id request-id x-request-id x-amzn-requestid].freeze

    # raw is what RubyLLM keeps of the answer, a Faraday response or the parsed body, or what a refusal carried.
    def self.from(raw)
      return nil if raw.nil?

      body = raw.respond_to?(:body) ? raw.body : raw
      in_body(body) || in_headers(raw.respond_to?(:headers) ? raw.headers : nil)
    end

    def self.in_body(body)
      return nil unless body.is_a?(Hash)

      BODY_KEYS.lazy.filter_map { |key| body[key].presence }.first&.to_s
    end

    # Header names are matched whatever their case, and a header given as a list (Net::HTTP's) gives its first value.
    def self.in_headers(headers)
      return nil if headers.blank?

      named = headers.to_h.transform_keys { |name| name.to_s.downcase }
      HEADERS.lazy.filter_map { |name| Array(named[name]).first.presence }.first&.to_s
    end
  end
end
