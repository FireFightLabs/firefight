module FirefightAi
  class Error < StandardError
    # The client error's own name, such as ContextLengthExceededError.
    attr_reader :reason

    def initialize(message = nil, reason: nil)
      @reason = reason || self.class.name.demodulize
      super(message)
    end
  end

  # Worth retrying, the provider was busy, slow, or briefly unavailable.
  class TransientError < Error; end

  # Retrying gives the same answer, bad request, auth, billing, context size, unknown model.
  class TerminalError < Error; end

  # The account paying for the model has no credit left, so nothing runs until someone adds some. Terminal, since
  # every retry is refused the same way.
  class OutOfCredit < TerminalError; end

  # A provider asked to wait while too much was in flight at once, which is a wait and never a spent balance.
  IN_FLIGHT = "InFlightBudget".freeze

  # Logged at error level, once per call refused for good, so alerting can watch for it.
  OUT_OF_CREDIT_EVENT = "ai.out_of_credit".freeze

  # Someone stopped the run while the model was answering.
  class Canceled < Error; end

  TRANSIENT_CLIENT_ERRORS = [
    RubyLLM::RateLimitError,
    RubyLLM::ServerError,
    RubyLLM::ServiceUnavailableError,
    RubyLLM::OverloadedError,
    Net::ReadTimeout,
    Faraday::TimeoutError
  ].freeze

  TERMINAL_CLIENT_ERRORS = [
    RubyLLM::ContextLengthExceededError,
    RubyLLM::BadRequestError,
    RubyLLM::UnauthorizedError,
    RubyLLM::ForbiddenError,
    RubyLLM::PaymentRequiredError,
    RubyLLM::ModelNotFoundError
  ].freeze

  # A provider's rate limit does not always arrive under the class the library has for it. OpenAI's
  # tokens per minute limit came back as a bad request, and a bad request is given up on, so the
  # status and the words decide before the class does.
  RATE_LIMIT_STATUS = 429
  RATE_LIMIT_WORDS = /rate limit/i

  def self.translating_errors
    yield
  rescue RubyLLM::CancelledError => e
    raise Canceled.new(e.message, reason: e.class.name.demodulize)
  rescue *TRANSIENT_CLIENT_ERRORS, *TERMINAL_CLIENT_ERRORS => e
    raise translated(e)
  end

  # Credit is read first, since OpenAI says a spent balance with the status of a rate limit.
  def self.translated(error)
    credit = Credit.from(error)
    return out_of_credit(error) if credit.out_of_credit?
    return TransientError.new(error.message, reason: IN_FLIGHT) if credit.in_flight?
    return TransientError.new(error.message, reason: error.class.name.demodulize) if TRANSIENT_CLIENT_ERRORS.any? { |kind| error.is_a?(kind) }
    return TransientError.new(error.message, reason: RubyLLM::RateLimitError.name.demodulize) if rate_limited?(error)

    TerminalError.new(error.message, reason: error.class.name.demodulize)
  end

  def self.out_of_credit(error)
    Rails.logger.error({ event: OUT_OF_CREDIT_EVENT, error_class: error.class.name, error: error.message }.to_json)
    OutOfCredit.new(error.message)
  end

  def self.rate_limited?(error)
    error.try(:response).try(:status) == RATE_LIMIT_STATUS || error.message.to_s.match?(RATE_LIMIT_WORDS)
  end
end
