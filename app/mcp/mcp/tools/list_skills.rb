module Mcp
  module Tools
    class ListSkills < Base
      tool_name FirefightTools::LIST_SKILLS
      authorize_as Ability::Action::RESOURCE_SKILLS
      description "List this workspace's own skills: recipes Halon loads beside Firefight's, each with its name, when Halon " \
                  "uses it, whether it is on, its version, the Firefight skill it is a copy of, and how many workflows run it. " \
                  "Read one whole with get_skill. Docs: #{Docs::SKILLS}"
      annotations(**READ_ONLY)
      own_words
      input_schema(properties: {}, required: [])

      def self.perform(workspace:, args:)
        skills = Chat::CustomSkill.where(workspace: workspace).live.with_usage_counts.includes(:live_version).ordered
        respond(skills: skills.map { |skill| summary(skill) })
      end

      def self.summary(skill)
        {
          id: skill.id, name: skill.name, when: skill.live_version.used_when, enabled: skill.enabled?, version: skill.live_version.number,
          copy_of: skill.library_name, workflows_running_it: skill.usage_count
        }.compact
      end

      # By id, or by name whatever its case.
      def self.find!(workspace, reference)
        skills = Chat::CustomSkill.where(workspace: workspace).live.includes(:live_version)
        wanted = reference.to_s.strip
        skills.find_by(id: wanted.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/) ? wanted : nil) ||
          skills.find_by(name: Chat::CustomSkill.normalize_value_for(:name, wanted)) || raise(ActiveRecord::RecordNotFound)
      end
    end
  end
end
