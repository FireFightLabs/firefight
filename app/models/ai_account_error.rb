# What went wrong with a workspace's own AI account, in plain words for the admin who set it up. Never the provider's
# own message whole, since it can carry a request id or part of a key, and never longer than one sentence or two.
module AiAccountError
  KEY_REASONS = %w[UnauthorizedError ForbiddenError].freeze
  BUSY_REASONS = %w[RateLimitError ServerError ServiceUnavailableError OverloadedError ReadTimeout TimeoutError InFlightBudget].freeze
  UNREACHABLE_REASONS = %w[ConnectionFailed SocketError SSLError].freeze
  SAID_LIMIT = 160

  # What a check can be refused with, besides a model call the engine translated.
  CHECK_ERRORS = [ FirefightAi::Error, RubyLLM::Error, RubyLLM::ConfigurationError, RubyLLM::ModelNotFoundError, Faraday::Error, SocketError ].freeze

  def self.words(error, model:)
    return "The account has no credit left." if AiPayer.out_of_credit?(error)

    case reason(error)
    when "UnauthorizedError" then "The provider refused the key."
    when "ForbiddenError" then "The key is not allowed to use #{model || 'this model'}."
    when "ModelNotFoundError" then "The provider does not offer #{model || 'this model'}."
    when "ConfigurationError" then "Some settings are missing."
    when *UNREACHABLE_REASONS then "The provider could not be reached at its address."
    when *BUSY_REASONS then "The provider was busy and did not answer. Check again in a minute."
    else "The provider answered with an error: #{said(error)}"
    end
  end

  def self.reason(error)
    error.is_a?(FirefightAi::Error) ? error.reason : error.class.name.demodulize
  end

  # The first line of what the provider said, with anything that looks like a credential taken out.
  def self.said(error)
    line = error.message.to_s.lines.first.to_s.strip
    text = Chat::SecretFree.redacted(line).truncate(SAID_LIMIT)
    text.presence || "#{reason(error)}."
  end
end
