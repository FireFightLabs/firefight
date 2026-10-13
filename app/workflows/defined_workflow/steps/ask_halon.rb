# Halon judges or summarises the data the step hands it and answers as fields: a verdict (ok, problem or unsure), a
# summary and any field the step asks for. It reads only what it is given and calls no tool, so it only reads.
class DefinedWorkflow::Steps::AskHalon < DefinedWorkflow::Steps::Base
  kind "ask_halon"
  label "Ask Halon"
  group GROUP_HALON

  KEY_QUESTION = "question".freeze
  KEY_DATA = "data".freeze
  KEY_FIELDS = "fields".freeze
  FIELD_NAME = "name".freeze
  FIELD_DESCRIPTION = "description".freeze
  FIELD_LIMIT = 10
  HANDED_OFF = "halon".freeze

  class << self
    def output_fields(config) = [ Workflow::HalonStep::VERDICT, Workflow::HalonStep::SUMMARY, *fields_of(config).map(&:first) ]

    def fields_of(config)
      Array(config[KEY_FIELDS]).filter_map do |field|
        next unless field.is_a?(Hash) && field[FIELD_NAME].to_s.match?(SolidWorkflow::Definition::STEP_NAME)

        [ field[FIELD_NAME].to_s, field[FIELD_DESCRIPTION].to_s ]
      end
    end

    def problems(step, workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      found = []
      found << "#{named} needs the question Halon answers." if config[KEY_QUESTION].to_s.strip.empty?
      found << "#{named} asks for at most #{FIELD_LIMIT} fields." if Array(config[KEY_FIELDS]).size > FIELD_LIMIT
      if fields_of(config).size != Array(config[KEY_FIELDS]).size
        found << "Each field #{named} asks for needs a name of lowercase letters, numbers and underscores."
      end
      found + super
    end

    def describe(config, _workspace) = config[KEY_QUESTION].to_s.truncate(200)
  end

  def perform
    answer = await(HANDED_OFF) { |name| WorkflowHalonStepJob.perform_later(@run.id, record&.id, @step.id, self.class.kind, @config, name) }
    return answer if answer.is_a?(SolidWorkflow::Park)
    raise Failed, answer[Workflow::HalonStep::KEY_ERROR] if answer[Workflow::HalonStep::KEY_ERROR]

    answer
  end
end
