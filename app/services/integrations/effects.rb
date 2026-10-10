module Integrations
  # What a connection tool's change does beyond its risk (Ability::Action::EFFECTS), from what its provider declares: the
  # tools its data_writes part names, and the registry's mitigation_tools and stopping_tools. A tool that only reads has
  # none.
  module Effects
    def self.of(tool)
      return [] if tool.read_only?

      entry = IntegrationProvider.find(tool.integration.provider)
      [
        (Ability::Action::EFFECT_DATA_WRITE if DataWrites.write_tool?(tool)),
        (Ability::Action::EFFECT_MITIGATION if entry&.mitigation_tools&.include?(tool.name)),
        (Ability::Action::EFFECT_STOPS if entry&.stopping_tools&.include?(tool.name))
      ].compact
    end
  end
end
