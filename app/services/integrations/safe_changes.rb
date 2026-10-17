module Integrations
  # Which changes are safe for Halon to make without asking, from what each provider declares (the registry's safe_tools
  # and safe_tools_without_undo), and which change who can reach something or a secret (access_tools), which a person is
  # always asked about. A tool on a remote server counts only through its own provider's list, so a native provider's
  # list never covers a tool of the same name on a server. A capability's change is decided call by call, since a
  # restart can reach a database and a scale can go down.
  module SafeChanges
    def self.tool?(tool) = undoable?(tool) || listed(tool, :safe_tools_without_undo)

    # Safe, and another tool puts it back, such as taking a label off again.
    def self.undoable?(tool) = listed(tool, :safe_tools)

    def self.access?(tool)
      entry = IntegrationProvider.find(tool.integration.provider)
      entry.present? && entry.access_tools.include?(tool.name)
    end

    # A restart of a service, which drops nothing it holds, or a scale above the count the map last read. A restart that
    # reaches a database or a machine, a scale down or to a count the map never read, and a rollback ask.
    def self.capability_call?(call, given)
      case call.spec.key
      when Capabilities::RESTART then call.resource&.kind == ResourceMap::KIND_SERVICE
      when Capabilities::SCALE then scales_up?(call, given)
      else false
      end
    end

    # A scale up is put back by scaling down again. A restart has nothing that puts it back.
    def self.capability_undoable?(call, given) = call.spec.key == Capabilities::SCALE && scales_up?(call, given)

    def self.scales_up?(call, given)
      now = Integer(call.resource&.details.to_h["instances"].to_s, exception: false)
      asked = Integer(given.to_h.stringify_keys["instances"].to_s, exception: false)
      !now.nil? && !asked.nil? && asked > now
    end
    private_class_method :scales_up?

    def self.listed(tool, list)
      return false if tool.read_only?

      entry = IntegrationProvider.find(tool.integration.provider)
      entry.present? && entry.kind == tool.integration.kind && entry.public_send(list).include?(tool.name)
    end
    private_class_method :listed
  end
end
