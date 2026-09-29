# A provider skill names the provider's tools. A connected server can drop or rename one, so once a day each provider
# skill is checked against the tools its provider still offers on any connection. A native pack's tools are in this
# repository, and a test holds its skills to them.
class SkillCheckJob < ApplicationJob
  queue_as :background

  def perform
    Chat::Skill.all.reject(&:firefight?).each do |skill|
      next if Integrations::NativePack.for(skill.source)

      offered = Integration::Tool.available.joins(:integration).where(integrations: { provider: skill.source }).distinct.pluck(:name)
      # Nobody has connected the provider, so there is nothing to check against.
      next if offered.empty?

      missing = skill.tools - offered
      next if missing.empty?

      Rails.logger.warn({ event: "skill.tools_missing", skill: skill.name, provider: skill.source, missing: missing }.to_json)
    end
  end
end
