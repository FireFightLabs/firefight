module Integrations
  # A general tool, such as an API request tool, both reads and changes things. A call its guard shows to read is a read
  # everywhere: no confirmation, no approval rule, and a member holds it by default like any tool that only reads
  # (AbilityGateway, Integration::Tool#reads_call?). A run that only reads may call such a tool too, as long as each call
  # is shown to read. Each provider whose tools mix the two says how to tell, and every other tool that is not read only
  # counts as a change on every call and is never offered to a run that only reads.
  #
  # A provider plugs in by naming its guard in its definition (Integrations::Provider, read_guard). The guard answers:
  #   guards?(tool_name)              whether it tells reads from changes for this tool
  #   reads?(tool_name, arguments)    whether this call only reads, true only when it can prove it
  #   reading(tool_name, arguments)   the call as a run that only reads makes it, raising PolicyRefusal for a change
  #   schema                          what a run that only reads is offered instead of the tool's own schema, or nil
  #   withheld(tool_name, arguments)  optional, why a read whose whole answer is a secret is refused, or nil
  #                                   (Integrations::SecretReads)
  # A guard's module also holds DESCRIPTION when it has a schema, which a run that only reads is told with it.
  module ReadGuards
    # Raised with a reason the agent can act on when a call is not shaped the way a guard reads it. A call that would
    # change something is refused by Firefight's rule instead (Integrations::PolicyRefusal).
    class Refused < StandardError; end

    # The guard for a tool that is not read only, or nil when nothing can tell its reads from its writes.
    def self.for(tool)
      return if tool.read_only?

      guard = Provider.for(tool.integration.provider).read_guard
      guard if guard&.guards?(tool.name)
    end

    # Whether a call to a tool that can make both was shown to read. A call the guard cannot prove reads counts as a change.
    def self.reads?(tool, arguments) = self.for(tool)&.reads?(tool.name, arguments.to_h.stringify_keys) == true

    # Whether a call only reads, because its tool only reads or its guard shows the call does.
    def self.read_call?(tool, arguments) = tool.read_only? || reads?(tool, arguments)
  end
end
