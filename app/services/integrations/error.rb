module Integrations
  # Base for anything that fails while talking to a provider, whatever the
  # executor kind. Callers rescue this, never a kind-specific subclass, so
  # rescue sites do not grow with new kinds.
  class Error < StandardError; end
end
