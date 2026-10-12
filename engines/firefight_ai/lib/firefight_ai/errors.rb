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

  # The model sent a reply whose tool call could not be read, again after being asked once more (Responder).
  class UnreadableReply < TerminalError; end

  # A provider asked to wait while too much was in flight at once, which is a wait and never a spent balance.
  IN_FLIGHT = "InFlightBudget".freeze

  # Logged at error level, once per call refused for good, so alerting can watch for it.
  OUT_OF_CREDIT_EVENT = "ai.out_of_credit".freeze

  # Someone stopped the run while the model was answering.
  class Canceled < Error; end

  # RubyLLM's error class says how a provider refused, such as a rate limit or a refused key, whatever words or status the
  # provider used. Text is read only where a provider still says a spent balance in words alone (Credit).
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

  # The provider did not answer after RubyLLM's own retries. It failed, was overloaded, kept refusing for rate, timed out
  # or could not be reached, and Halon's loop carries on with a backup model.
  PROVIDER_DOWN_ERRORS = [
    RubyLLM::RateLimitError,
    RubyLLM::ServerError,
    RubyLLM::ServiceUnavailableError,
    RubyLLM::OverloadedError,
    Net::ReadTimeout,
    Faraday::TimeoutError,
    Faraday::ConnectionFailed
  ].freeze

  # The provider refused the account itself rather than the call, such as a revoked key or one not allowed the model.
  KEY_REFUSED_ERRORS = [ RubyLLM::UnauthorizedError, RubyLLM::ForbiddenError ].freeze
  # The same, once translated, by the reason a FirefightAi::Error keeps.
  KEY_REFUSED_REASONS = KEY_REFUSED_ERRORS.map { |kind| kind.name.demodulize }.freeze

  # The provider says the model is not there for this account, such as Claude on a Vertex AI project that has not enabled
  # it. Another model on the same account may well be. RubyLLM has no class of its own for it.
  MODEL_UNAVAILABLE_STATUS = 404

  # Why a call was refused, which the app records a switch of model with. Credit is read first, since a provider can say a
  # spent balance under the class of a rate limit or a refused key.
  CAUSE_OUT_OF_CREDIT = :out_of_credit
  CAUSE_KEY_REFUSED = :key_refused
  CAUSE_UNAVAILABLE = :unavailable
  CAUSE_DOWN = :down

  def self.cause(error)
    return CAUSE_OUT_OF_CREDIT if error.is_a?(OutOfCredit) || (error.is_a?(RubyLLM::Error) && Credit.from(error).out_of_credit?)
    return CAUSE_KEY_REFUSED if key_refused?(error)
    return CAUSE_UNAVAILABLE if model_unavailable?(error)

    CAUSE_DOWN
  end

  def self.key_refused?(error)
    KEY_REFUSED_ERRORS.any? { |kind| error.is_a?(kind) } || (error.is_a?(Error) && KEY_REFUSED_REASONS.include?(error.reason))
  end

  def self.model_unavailable?(error) = error.is_a?(RubyLLM::Error) && error.try(:response).try(:status) == MODEL_UNAVAILABLE_STATUS

  # Halon's loop carries on with a backup when the provider is down or the model is not there for the account.
  def self.backup_helps?(error) = provider_down?(error) || model_unavailable?(error)

  # Credit is the payer's to fix and a wait for spend in flight clears by itself, so neither is the provider being down.
  def self.provider_down?(error)
    return false unless PROVIDER_DOWN_ERRORS.any? { |kind| error.is_a?(kind) }

    credit = Credit.from(error)
    !credit.out_of_credit? && !credit.in_flight?
  end

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

    TerminalError.new(error.message, reason: error.class.name.demodulize)
  end

  def self.out_of_credit(error)
    Rails.logger.error({ event: OUT_OF_CREDIT_EVENT, error_class: error.class.name, error: error.message }.to_json)
    OutOfCredit.new(error.message)
  end
end
