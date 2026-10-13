module Mcp
  module Tools
    class GetSkill < Base
      tool_name GET_SKILL
      authorize_as Ability::Action::RESOURCE_SKILLS
      behind_flag FeatureFlags::CUSTOM_SKILLS
      description "Read one of this workspace's skills whole, by its name or id: when Halon uses it, the tools it names, its " \
                  "steps, whether it is on, and version_id, which upsert_skill takes to refuse a change made over someone " \
                  "else's. Docs: #{Docs::SKILLS}"
      annotations(**READ_ONLY)
      own_words
      input_schema(
        properties: {
          skill: { type: "string", description: "The skill's name or id" }
        },
        required: [ "skill" ]
      )

      def self.perform(workspace:, args:)
        skill = ListSkills.find!(workspace, args[:skill])
        respond(detail(skill))
      end

      def self.detail(skill)
        version = skill.live_version
        ListSkills.summary(Chat::CustomSkill.with_usage_counts.find(skill.id))
                  .merge(tools: version.tools, steps: version.steps, version_id: version.id, updated_by: version.author_words)
      end
    end
  end
end
