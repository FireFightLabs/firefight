# A provider skill names the provider's tools. A connected server can drop or rename one, so once a day each provider
# skill is checked against the tools its provider still offers on any connection, and what is gone is recorded for
# whoever runs Firefight. A native pack's tools are in this repository, and a test holds its skills to them.
class SkillCheckJob < ApplicationJob
  queue_as :background

  def perform
    skills = Chat::Skill.all.reject { |skill| skill.firefight? || Integrations::NativePack.for(skill.source) }
    # The map is Firefight's own, so a provider cannot drop it.
    missing = skills.to_h { |skill| [ skill.name, skill.tools - offered(skill.source) - [ Chat::Tools::UseSkill::MAP ] ] }.reject { |_skill, tools| tools.empty? }

    Chat::SkillProblem.record!(missing, provider_of: skills.to_h { |skill| [ skill.name, skill.source ] })
  end

  private

  # Every tool any connection to the provider still offers, and every capability one of them answers, since a skill
  # names a capability rather than the tool it runs as. Nobody having connected it leaves nothing to check against, so
  # it counts as offering all of them.
  def offered(provider)
    @offered ||= {}
    @offered[provider] ||= begin
      names = Integration::Tool.available.joins(:integration).where(integrations: { provider: provider }).distinct.pluck(:name)
      capabilities = Integrations::Capabilities.tool_names.select { |name| names.include?(Integrations::Capabilities.provider_tool(provider, name)) }
      (names + capabilities).presence || Chat::Skill.all.select { |skill| skill.source == provider }.flat_map(&:tools)
    end
  end
end
