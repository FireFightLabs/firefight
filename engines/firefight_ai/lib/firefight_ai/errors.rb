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
  rescue *TRANSIENT_CLIENT_ERRORS => e
    raise TransientError.new(e.message, reason: e.class.name.demodulize)
  rescue *TERMINAL_CLIENT_ERRORS => e
    raise TransientError.new(e.message, reason: RubyLLM::RateLimitError.name.demodulize) if rate_limited?(e)

    raise TerminalError.new(e.message, reason: e.class.name.demodulize)
  end

  def self.rate_limited?(error)
    error.try(:response).try(:status) == RATE_LIMIT_STATUS || error.message.to_s.match?(RATE_LIMIT_WORDS)
  end
end
