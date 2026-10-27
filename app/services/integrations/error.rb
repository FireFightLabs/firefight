module Integrations
  # Callers rescue this, never a kind-specific subclass, so rescue sites do not
  # grow with new kinds.
  class Error < StandardError
    # The HTTP status a provider answered with, when the error is its answer.
    attr_accessor :http_status
  end

  # One of Firefight's own rules refused the call, never the provider, such as a protected branch, a path Halon may not
  # change or a statement that would write. Its message is the rule's sentence, which says where it is changed when it
  # is a setting. It is final, so the agent is told so and never tries another way around it.
  class PolicyRefusal < Error; end

  # Something this install cannot do right now, whatever the arguments, such as a code sandbox that cannot start.
  # Its message tells the agent so, since trying again with other arguments only spends turns.
  class Unavailable < Error; end

  # A provider answered 429, too many requests. A sweep stops reading that connection until its next run, and a call
  # says so in words. Every client's rate limit error is one of these as well as its own error, so a caller rescues it
  # once whatever the provider, and a rescue of the client's own error still catches it.
  module RateLimited; end

  # A provider answered that the thing a call named is not there, a 404 or the provider's own word for one. Every client's
  # not found error is one of these as well as its own, so a caller tells it from a failure without naming the provider.
  module NotFound; end

  # A provider's host did not answer in time. Every client's error for it is one of these as well as its own, so a caller
  # tells a slow provider from a refusal without naming the provider.
  module TimedOut; end

  # A provider's host could not be reached at all, as a connection refused or dropped, a name that did not resolve or a
  # handshake that failed. Nothing was answered, so a caller tries again rather than reading it as the host's refusal.
  module Unreachable; end

  # The provider refused the credential Firefight calls with, or a permission it lacks, never the thing the call named,
  # such as a token that expired or lost a scope, or an app not granted what the call needs. Every client's error for it
  # is one of these as well as its own, so a caller tells Firefight's own access from the provider's answer about the
  # thing without naming the provider.
  module NotAuthorized; end
end
