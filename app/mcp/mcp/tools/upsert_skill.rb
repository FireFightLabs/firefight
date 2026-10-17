module Mcp
  module Tools
    class UpsertSkill < Base
      tool_name FirefightTools::UPSERT_SKILL
      description "Add one of this workspace's own skills, or change one by its name or id. Halon loads a skill when a " \
                  "question fits, and the tools it names become callable as far as the asker may use them. To change a skill, " \
                  "pass skill and only what changes, with version_id from get_skill so a change made over someone else's is " \
                  "refused rather than written over it. Every change is a new version. enabled turns it off or on: off, Halon " \
                  "no longer loads it and a workflow step that runs it is refused. If the call requires approval, retry the " \
                  "identical call with approval_id once approved. Docs: #{Docs::SKILLS}"
      annotations(**WRITE)
      own_words
      input_schema(
        properties: {
          skill: { type: "string", description: "The name or id of the skill to change. Omit to add one. An unknown skill is an error, not an add" },
          name: { type: "string", description: "The skill's name, lowercase words joined by underscores, required to add one" },
          when: { type: "string", description: "When Halon uses it, one sentence, at most #{Chat::CustomSkill::Version::WHEN_LIMIT} characters" },
          tools: { type: "array", items: { type: "string" }, description: "The tools its steps call, by the names Halon calls them" },
          steps: { type: "string", description: "The numbered steps in Markdown, each tool named in backticks" },
          reason: { type: "string", description: "What changed and why, kept with the version" },
          enabled: { type: "boolean", description: "Turn the skill on or off" },
          version_id: { type: "string", description: "The version_id get_skill gave, to refuse a change made over someone else's" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )

      # Decided from the arguments alone, so a caller who may not change skills is refused before learning which exist.
      def self.authorization(_workspace, args)
        [ Ability::Action::RESOURCE_SKILLS, args[:skill].present? ? Ability::Action::ACTION_UPDATE : Ability::Action::ACTION_CREATE ]
      end

      def self.perform_with_principal(workspace:, principal:, args:)
        service = Chat::CustomSkillService.new(workspace)
        author = principal.is_a?(WorkspaceMembership) ? principal : nil
        content = { "when" => args[:when], "tools" => args[:tools], "steps" => args[:steps] }
        skill = args[:skill].present? ? ListSkills.find!(workspace, args[:skill]) : nil
        written = if skill
          service.update!(skill, by: author, content: content, name: args[:name], reason: args[:reason], seen: args[:version_id], enabled: args[:enabled])
        else
          service.create!(name: args[:name], content: content, by: author, reason: args[:reason], enabled: args[:enabled])
        end
        respond(GetSkill.detail(written.reload))
      rescue Chat::CustomSkillService::Refused => error
        refuse(error: error.message)
      rescue ActiveRecord::RecordInvalid => error
        refuse(error: error.record.errors.full_messages.to_sentence)
      end
    end
  end
end
