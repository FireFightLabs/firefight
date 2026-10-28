module FirefightAi
  # Whether a provider refused a call because the account paying for it has no credit left. RubyLLM raises a
  # PaymentRequiredError for a 402 and for Anthropic's "credit balance is too low", so the class decides first. Some
  # providers still say it under another class, which only their code or their words tell apart.
  class Credit
    PAYMENT_REQUIRED = 402
    # The error codes that mean a spent balance whatever the status they come with. OpenAI says it with a 429 whose code
    # is insufficient_quota, and Z.AI with a 429 whose code is 1113, which RubyLLM raises as a rate limit
    # (docs.z.ai/api-reference/api-code). Model Studio says an overdue account, a spent budget or a spent free quota under
    # codes of its own, as a 400, 403 or 429 (alibabacloud.com/help/en/model-studio/error-code).
    QUOTA_CODES = %w[
      insufficient_quota 1113
      Arrearage isv.OUT_OF_SERVICE PrepaidBillOverdue PostpaidBillOverdue BudgetLimitExceeded AllocationQuota.FreeTierOnly Throttling.AllocationQuota
    ].freeze
    # MiniMax says a spent balance or credit in base_resp.status_code (platform.minimax.io/docs/api-reference/errorcode).
    BALANCE_STATUS_CODES = [ 1008, 2053 ].freeze
    # Said only in words under a class that means something else, by Anthropic's usage limit (a bad request), Gemini's
    # spent prepayment (a rate limit), OpenRouter's key spending limit (the key refused, seen live as "something went
    # wrong") and xAI's team out of credits or at its monthly spending limit. The code fix proxy reads the provider's own
    # answer, so Anthropic's balance too low is here for it.
    OUT_OF_CREDIT_PHRASES = [
      "credit balance is too low", "prepayment credits are depleted", "key limit exceeded",
      "reached your specified api usage limits", "reached your specified workspace usage limits",
      "reached its monthly spending limit"
    ].freeze
    OUT_OF_CREDIT_WORDS = Regexp.new(OUT_OF_CREDIT_PHRASES.map { |phrase| Regexp.escape(phrase) }.join("|"), Regexp::IGNORECASE)
    # OpenRouter's 402 for too much spend in flight at once, which clears by itself and says when.
    IN_FLIGHT_SOURCE = "openrouter_in_flight_budget".freeze
    # OpenRouter's metadata.limit_source for a spent balance, key limit, guardrail budget or workspace budget. The budgets
    # come back as a 403 whose words change with each one, so the source decides.
    SPENT_SOURCES = %w[openrouter_credits openrouter_key_limit openrouter_guardrail_budget openrouter_workspace_budget].freeze
    RETRY_AFTER = "retry-after".freeze

    # From a client library error, which carries the response it came from when there was one.
    def self.from(error)
      response = error.try(:response)
      new(status: status_of(response), body: response.try(:body), message: error.message, headers: headers_of(response),
          payment_required: error.is_a?(RubyLLM::PaymentRequiredError))
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

    # payment_required is whether RubyLLM raised the refusal as a PaymentRequiredError.
    def initialize(status:, body:, message: nil, headers: {}, payment_required: false)
      @status = status
      @payment_required = payment_required
      @error = error_object(body)
      @status_code = base_resp_code(body)
      @words = [ message, @error["message"] ].compact.join(" ")
      @headers = headers || {}
    end

    def out_of_credit?
      return false if in_flight?

      @payment_required || @status == PAYMENT_REQUIRED || QUOTA_CODES.include?(@error["code"].to_s) || QUOTA_CODES.include?(@error["type"].to_s) ||
        SPENT_SOURCES.include?(limit_source) || BALANCE_STATUS_CODES.include?(@status_code) || @words.match?(OUT_OF_CREDIT_WORDS)
    end

    # A wait-and-retry, never a spent balance. OpenRouter documents a 402 with Retry-After as the only one to retry.
    def in_flight?
      @status == PAYMENT_REQUIRED && (@headers[RETRY_AFTER].present? || limit_source == IN_FLIGHT_SOURCE)
    end

    private

    def limit_source = @error.dig("metadata", "limit_source").to_s

    # Providers nest it under "error", as a parsed hash or as the raw JSON text.
    def error_object(body)
      found = parsed(body)["error"]
      found.is_a?(Hash) ? found : {}
    end

    def base_resp_code(body)
      code = parsed(body).dig("base_resp", "status_code")
      code.to_i if code.present?
    end

    def parsed(body)
      found = body.is_a?(String) ? JSON.parse(body) : body
      found.is_a?(Hash) ? found.deep_stringify_keys : {}
    rescue JSON::ParserError
      {}
    end
  end
end
