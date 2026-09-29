# A provider skill that names tools its provider no longer offers on any connection. The daily check replaces the whole
# set, so a skill that was fixed, or no longer exists, drops out. created_at is when the problem was first seen.
class Chat::SkillProblem < ApplicationRecord
  self.table_name = "chat_skill_problems"

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
