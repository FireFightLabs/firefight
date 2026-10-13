module Mcp
  module Tools
    class DeleteSkill < Base
      tool_name DELETE_SKILL
      behind_flag FeatureFlags::CUSTOM_SKILLS
      description "Delete one of this workspace's skills by its name or id, with every version. Halon stops loading it at once, " \
                  "and a copy of one of Firefight's skills gives Firefight's back. A skill a workflow runs is refused with how " \
                  "many, so turn it off with upsert_skill instead. If the call requires approval, retry the identical call with " \
                  "approval_id once approved. Docs: #{Docs::SKILLS}"
      annotations(**DESTRUCTIVE)
      ends_something
      authorize_as Ability::Action::RESOURCE_SKILLS, Ability::Action::ACTION_DELETE
      input_schema(
        properties: {
          skill: { type: "string", description: "The skill's name or id" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "skill" ]
      )

      def self.perform(workspace:, args:)
        skill = ListSkills.find!(workspace, args[:skill])
        Chat::CustomSkillService.new(workspace).delete!(skill)
        respond(id: skill.id, name: skill.name, deleted: true)
      rescue Chat::CustomSkillService::Refused => error
        refuse(error: error.message)
      end
    end
  end
end
