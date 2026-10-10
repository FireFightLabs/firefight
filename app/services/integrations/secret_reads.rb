module Integrations
  # A read whose whole answer is a secret, such as a tunnel's token or a database's connection string, is refused before
  # it runs, for every caller, since no masking of the answer leaves anything worth reading. A read that answers a secret
  # beside what is worth reading keeps the rest and loses the secret on the way out (Integrations::Redactions).
  #
  # A provider plugs in through its definition (Integrations::Provider): withheld_tools names a tool, by the name its
  # server gives it, with the sentence that says why and what to read instead. A tool that reaches anything, such as an
  # API request tool, says it per call through its read guard's withheld(tool_name, arguments), which answers that
  # sentence or nil.
  module SecretReads
    def self.refusal(tool, arguments)
      provider = Provider.for(tool.integration.provider)
      named = provider.withheld_tools[tool.remote_name.to_s]
      return named if named

      guard = provider.read_guard
      guard.withheld(tool.name, arguments.to_h.stringify_keys) if guard.respond_to?(:withheld) && guard.guards?(tool.name)
    end

    def self.refuse!(tool, arguments)
      refused = refusal(tool, arguments)
      raise PolicyRefusal, refused if refused
    end
  end
end
