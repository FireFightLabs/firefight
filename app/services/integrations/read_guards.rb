module Integrations
  # A run that only reads, such as an investigation, may still call a tool that can both read and write, as long as the
  # call itself is shown to read. Each provider whose tools mix the two says how to tell, and every other tool that is
  # not read only is never offered to such a run.
  module ReadGuards
    # Raised with a reason the agent can act on when a call would not only read.
    class Refused < StandardError; end

    # The guard for a tool that is not read only, or nil when nothing can tell its reads from its writes. A provider's
    # definition names its guard (Integrations::Provider, read_guard), which answers guards?(tool_name), schema and
    # reading(tool_name, arguments). A guard's schema, when it has one, is what a run that only reads is offered instead
    # of the tool's own, with its description.
    def self.for(tool)
      guard = Provider.for(tool.integration.provider).read_guard
      guard if guard&.guards?(tool.name)
    end
  end
end
