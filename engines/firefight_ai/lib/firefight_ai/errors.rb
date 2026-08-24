module FirefightAi
  # The engine's own error family. Callers retry on Transient and stop on
  # Terminal without ever naming the client library underneath.
  class Error < StandardError
    # The client error's own name, so a failure can be reported by cause
    # ("ContextLengthExceededError") without exposing the client library.
    attr_reader :reason

    def initialize(message = nil, reason: nil)
      @reason = reason || self.class.name.demodulize
      super(message)
    end
  end

  # Worth retrying: the provider was busy, slow, or briefly unavailable.
  class TransientError < Error; end

  # Retrying gives the same answer: bad request, auth, billing, context size,
  # unknown model.
  class TerminalError < Error; end

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

  # Every model call runs inside this block, so the client library's error
  # taxonomy stops at the engine boundary.
  def self.translating_errors
    yield
  rescue *TRANSIENT_CLIENT_ERRORS => e
    raise TransientError.new(e.message, reason: e.class.name.demodulize)
  rescue *TERMINAL_CLIENT_ERRORS => e
    raise TerminalError.new(e.message, reason: e.class.name.demodulize)
  end
end
