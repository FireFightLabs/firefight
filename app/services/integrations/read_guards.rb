module Integrations
  # A run that only reads, such as an investigation, may still call a tool that can both read and write, as long as the
  # call itself is shown to read. Each provider whose tools mix the two says how to tell, and every other tool that is
  # not read only is never offered to such a run.
  module ReadGuards
    # Raised with a reason the agent can act on when a call would not only read.
    class Refused < StandardError; end

    GUARDS = { "northflank" => "Integrations::ReadGuards::Northflank", "cloudflare" => "Integrations::ReadGuards::Cloudflare" }.freeze

    # The guard for a tool that is not read only, or nil when nothing can tell its reads from its writes. A guard's schema,
    # when it has one, is what a run that only reads is offered instead of the tool's own, with its description.
    def self.for(tool)
      guard = GUARDS[tool.integration.provider]&.constantize
      guard if guard&.guards?(tool.name)
    end
  end
end
