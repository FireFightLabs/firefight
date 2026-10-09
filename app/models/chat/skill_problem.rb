# A provider skill that names tools its provider no longer offers on any connection. The daily check replaces the whole
# set, so a skill that was fixed, or no longer exists, drops out. created_at is when the problem was first seen.
class Chat::SkillProblem < ApplicationRecord
  self.table_name = "chat_skill_problems"

  # A provider skill names the provider's tools. A connected server can drop or rename one, so each provider skill is
  # checked against the tools its provider still offers on any connection, and what is gone is recorded for whoever
  # runs Firefight. A native pack's tools are in this repository, and a test holds its skills to them.
  def self.check!
    skills = Chat::Skill.all.reject { |skill| skill.firefight? || Integrations::NativePack.for(skill.source) }
    offered = Hash.new { |known, provider| known[provider] = offered_by(provider) }
    # The map is Firefight's own, so a provider cannot drop it.
    missing = skills.to_h { |skill| [ skill.name, skill.tools - offered[skill.source] - [ Mcp::Tools::GET_RESOURCE_MAP ] ] }.reject { |_skill, tools| tools.empty? }

    record!(missing, provider_of: skills.to_h { |skill| [ skill.name, skill.source ] })
  end

  # Every tool any connection to the provider still offers, and every capability one of them answers, since a skill
  # names a capability rather than the tool it runs as. Nobody having connected it leaves nothing to check against, so
  # it counts as offering all of them.
  def self.offered_by(provider)
    names = Integration::Tool.available.joins(:integration).where(integrations: { provider: provider }).distinct.pluck(:name)
    capabilities = Integrations::Capabilities.tool_names.select { |name| names.include?(Integrations::Capabilities.provider_tool(provider, name)) }
    (names + capabilities).presence || Chat::Skill.all.select { |skill| skill.source == provider }.flat_map(&:tools)
  end
  private_class_method :offered_by

  # missing maps a skill to the tools gone from its provider.
  def self.record!(missing, provider_of:, at: Time.current)
    transaction do
      where.not(skill: missing.keys).delete_all
      missing.each do |skill, tools|
        problem = find_or_initialize_by(skill: skill)
        problem.update!(provider: provider_of.fetch(skill), missing_tools: tools, checked_at: at)
      end
    end
  end
end
