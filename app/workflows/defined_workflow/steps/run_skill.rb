# Halon follows one skill, Firefight's own or a connected provider's, with only the tools that skill names, and reports
# a verdict, a summary, a severity for a problem and what it found. It only reads, whatever the skill's tools could do,
# since a change made by a model has no undo written ahead and no check after it.
class DefinedWorkflow::Steps::RunSkill < DefinedWorkflow::Steps::Base
  kind "run_skill"
  label "Run a skill"
  group GROUP_HALON

  KEY_SKILL = "skill".freeze
  KEY_FOCUS = "focus".freeze
  FOCUS_LIMIT = 2_000
  HANDED_OFF = "halon".freeze

  class << self
    def checks?(_config, _workspace) = true

    def output_fields(_config)
      [ Workflow::HalonStep::VERDICT, Workflow::HalonStep::SUMMARY, Workflow::HalonStep::SEVERITY, Workflow::HalonStep::FINDINGS ]
    end

    def problems(step, workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      return [ "#{named} needs the skill Halon follows." ] if config[KEY_SKILL].to_s.strip.empty?
      return [ "#{named} follows #{config[KEY_SKILL]}, which is not a skill for this workspace's connections." ] unless skill(config, workspace)
      return [ "#{named} says what to look at in at most #{FOCUS_LIMIT} characters." ] if config[KEY_FOCUS].to_s.length > FOCUS_LIMIT

      super
    end

    def reach(config, workspace)
      found = skill(config, workspace)
      found ? DefinedWorkflow::Reach.for_skill(workspace, found) : []
    end

    def skill(config, workspace) = Chat::Skill.available_to(workspace).find { |each| each.name == config[KEY_SKILL].to_s }

    def describe(config, _workspace) = [ config[KEY_SKILL], config[KEY_FOCUS].presence ].compact.join(": ").truncate(200)
  end

  def perform
    answer = await(HANDED_OFF) { WorkflowHalonStepJob.perform_later(@run.id, record&.id, @step.id, self.class.kind, @config) }
    return answer if answer.is_a?(SolidWorkflow::Park)
    raise Failed, answer[Workflow::HalonStep::KEY_ERROR] if answer[Workflow::HalonStep::KEY_ERROR]

    answer
  end
end
