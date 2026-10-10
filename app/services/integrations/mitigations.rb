module Integrations
  # Whether one call is a change customers feel for a while (Ability::Action::EFFECT_MITIGATION), so it is undone after a
  # time unless someone keeps it. A tool whose every change is one says so for the whole tool (Integrations::Effects). A
  # general tool that reaches a whole API is told call by call by its provider's mitigation_reader, the way a read guard
  # tells its reads, which answers mitigation?(tool, arguments) from the provider's own arguments.
  module Mitigations
    def self.call?(tool, arguments)
      return false if tool.read_only?
      return true if tool.ability_action&.effect?(Ability::Action::EFFECT_MITIGATION)

      reader = Provider.for(tool.integration.provider).mitigation_reader
      reader.present? && reader.mitigation?(tool, arguments.to_h.stringify_keys) == true
    end
  end
end
