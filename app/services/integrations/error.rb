module Integrations
  # Callers rescue this, never a kind-specific subclass, so rescue sites do not
  # grow with new kinds.
  class Error < StandardError; end
end
