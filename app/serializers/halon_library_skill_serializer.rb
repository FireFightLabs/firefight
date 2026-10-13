# One of Firefight's skills as the Skills page's library lists it, with its version and whether the workspace has a copy.
# Its steps are sent only for the one opened, since the library holds hundreds.
class HalonLibrarySkillSerializer < BaseSerializer
  object_as :skill

  type :string
  def name = skill.name

  # Whose tools it drives, such as Firefight or Northflank.
  type :string
  def source = skill.firefight? ? "Firefight" : Chat::Tools::Docs.provider_name(skill.source)

  type :string
  def domain = skill.domain.humanize

  type :string
  def used_when = skill.used_when

  type "string[]"
  def tools = skill.tools

  type :number
  def version = skill.version

  type :boolean
  def copied = options.fetch(:copied, []).include?(skill.name)

  type :string, optional: true
  def copy_blocked_reason = Chat::CustomSkill.copy_blocked_reason(skill, copied: options.fetch(:copied, []))

  type :string, optional: true
  def steps = (skill.steps if options[:with_steps])
end
