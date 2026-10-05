module Integrations
  # Callers rescue this, never a kind-specific subclass, so rescue sites do not
  # grow with new kinds.
  class Error < StandardError; end

  # Something this install cannot do right now, whatever the arguments, such as a code sandbox that cannot start.
  # Its message tells the agent so, since trying again with other arguments only spends turns.
  class Unavailable < Error; end

  # A provider answered 429, too many requests. A sweep stops reading that connection until its next run, and a call
  # says so in words. Every client's rate limit error is one of these as well as its own error, so a caller rescues it
  # once whatever the provider, and a rescue of the client's own error still catches it.
  module RateLimited; end
end
