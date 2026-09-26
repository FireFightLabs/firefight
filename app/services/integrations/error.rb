module Integrations
  # Callers rescue this, never a kind-specific subclass, so rescue sites do not
  # grow with new kinds.
  class Error < StandardError; end

  # Something this install cannot do right now, whatever the arguments, such as a code sandbox that cannot start.
  # Its message tells the agent so, since trying again with other arguments only spends turns.
  class Unavailable < Error; end
end
