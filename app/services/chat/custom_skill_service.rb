# Writes a workspace's own skill the same way from every way in: the Skills page, the API and MCP. The tools a skill
# names are checked against what Halon has here before anything is written, which needs the tool catalog, so it lives
# here rather than on the model. Only what is given changes, and a change lands as a new version on the one the writer
# saw.
class Chat::CustomSkillService
  Refused = Chat::CustomSkill::Writing::Refused
  # The tools named are not ones Halon has here, which a form shows beside its tools.
  class ToolsRefused < Refused; end

  def initialize(workspace)
    @workspace = workspace
  end

  def create!(name:, content:, by:, reason: nil)
    check_tools!(content["tools"])
    Chat::CustomSkill.create_with!(workspace: @workspace, name: name, content: content, by: by, reason: reason)
  end

  # content holds only the parts that change. enabled, when given, turns it on or off without a new version.
  def update!(skill, by:, content: {}, name: nil, reason: nil, seen: nil, enabled: nil)
    changed = content.compact
    Chat::CustomSkill.transaction do
      if changed.any? || (name.present? && name != skill.name)
        merged = skill.live_version.content.merge(changed)
        check_tools!(merged["tools"], skill: skill)
        skill.write!(merged, by: by, reason: reason, seen: seen.presence || skill.live_version_id, name: name.presence || skill.name)
      end
      skill.switch!(on: enabled) unless enabled.nil?
    end
    skill.reload
  end

  def delete!(skill)
    blocked = Chat::CustomSkill.with_usage_counts.find(skill.id).deletion_blocked_reason
    raise Refused, blocked if blocked

    skill.destroy!
  end

  private

  def check_tools!(tools, skill: nil)
    problem = Chat::Tools::SkillTools.problem(@workspace, tools, skill: skill)
    raise ToolsRefused, problem if problem
  end
end
