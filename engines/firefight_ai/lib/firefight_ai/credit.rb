module FirefightAi
  # Whether a provider refused a call because the account paying for it has no credit left. Each provider says it its own
  # way, so this reads the status, the error's code and its words.
  class Credit
    PAYMENT_REQUIRED = 402
    # OpenAI says a spent balance with a 429 whose code is insufficient_quota, which is not a rate limit to wait out.
    QUOTA_CODES = %w[insufficient_quota].freeze
    # Said only in words: Anthropic's balance too low or its usage limit reached (a 400), Gemini's prepaid balance spent
    # (a 429), OpenRouter's key spending limit reached (a 403, "Key limit exceeded (total limit)") and its credits spent,
    # and DeepSeek's balance spent. Seen live, OpenRouter's 403 reached a chat as "something went wrong".
    OUT_OF_CREDIT_PHRASES = [
      "credit balance is too low", "prepayment credits are depleted", "key limit exceeded", "insufficient credits",
      "reached your specified api usage limits", "reached your specified workspace usage limits", "insufficient balance"
    ].freeze
    OUT_OF_CREDIT_WORDS = Regexp.new(OUT_OF_CREDIT_PHRASES.map { |phrase| Regexp.escape(phrase) }.join("|"), Regexp::IGNORECASE)
    # OpenRouter's 402 for too much spend in flight at once, which clears by itself and says when.
    IN_FLIGHT_SOURCE = "openrouter_in_flight_budget".freeze
    RETRY_AFTER = "retry-after".freeze

    # From a client library error, which carries the response it came from when there was one.
    def self.from(error)
      response = error.try(:response)
      new(status: status_of(response), body: response.try(:body), message: error.message, headers: headers_of(response))
    end

    def self.status_of(response)
      status = response.respond_to?(:status) ? response.status : response.try(:[], :status)
      status&.to_i
    end

    def self.headers_of(response)
      headers = response.respond_to?(:headers) ? response.headers : response.try(:[], :response_headers)
      headers.respond_to?(:to_h) ? headers.to_h.transform_keys { |name| name.to_s.downcase } : {}
    rescue StandardError
      {}
    end

    def initialize(status:, body:, message: nil, headers: {})
      @status = status
      @error = error_object(body)
      @words = [ message, @error["message"] ].compact.join(" ")
      @headers = headers || {}
    end

    def out_of_credit?
      return false if in_flight?

      @status == PAYMENT_REQUIRED || QUOTA_CODES.include?(@error["code"].to_s) || QUOTA_CODES.include?(@error["type"].to_s) ||
        @words.match?(OUT_OF_CREDIT_WORDS)
    end

    # A wait-and-retry, never a spent balance. OpenRouter documents a 402 with Retry-After as the only one to retry.
    def in_flight?
      @status == PAYMENT_REQUIRED && (@headers[RETRY_AFTER].present? || @error.dig("metadata", "limit_source") == IN_FLIGHT_SOURCE)
    end

    private

    # Providers nest it under "error", as a parsed hash or as the raw JSON text.
    def error_object(body)
      parsed = body.is_a?(String) ? JSON.parse(body) : body
      found = parsed.is_a?(Hash) ? parsed["error"] || parsed[:error] : nil
      found.is_a?(Hash) ? found.deep_stringify_keys : {}
    rescue JSON::ParserError
      {}
    end
  end
end
