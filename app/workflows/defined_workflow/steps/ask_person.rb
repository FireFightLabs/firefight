# Asks a person a question in a direct message and on the run's page, and waits for the answer: one of a few choices,
# each a route out of the step, or a short form whose answers later steps read by name. Anyone it asked can answer, the
# first answer counts, and in a test run the person testing can answer too. A question nobody answers within the step's
# time limit is withdrawn and the step takes its unanswered route. Asking reads nothing outside the run, so it needs no
# grant.
class DefinedWorkflow::Steps::AskPerson < DefinedWorkflow::Steps::Base
  kind "ask_person"
  label "Ask a person"
  group GROUP_PEOPLE

  PEOPLE = DefinedWorkflow::Steps::People
  QUESTION = Workflow::Run::Question
  KEY_QUESTION = "question".freeze
  KEY_DETAILS = "details".freeze
  KEY_CHOICES = "choices".freeze
  KEY_FIELDS = "fields".freeze
  FIELD_NAME = QUESTION::FIELD_NAME
  FIELD_LABEL = QUESTION::FIELD_LABEL
  OUTPUT_ANSWER = "answer".freeze
  OUTPUT_ANSWERED_BY = "answered_by".freeze
  ROUTE_ANSWERED = "answered".freeze
  ROUTE_UNANSWERED = "unanswered".freeze
  CHOICE_LIMIT = QUESTION::CHOICE_LIMIT
  FIELD_LIMIT = QUESTION::FIELD_LIMIT
  QUESTION_LIMIT = 1_000
  # How long a question waits for an answer when the step sets no time limit of its own.
  ANSWER_LIMIT = 24.hours
  ASKED = "answer".freeze

  config_help "#{PEOPLE.help} question (what they are asked, may use references), details (optional, may use references), choices " \
              "(up to #{CHOICE_LIMIT} names, lowercase with underscores, each a route out of the step and shown humanized), fields (a short " \
              "form, up to #{FIELD_LIMIT} {name, label}). It needs choices, fields or both. Takes the chosen choice's route, or answered " \
              "when it has no choices, and unanswered when nobody answers within its time limit (#{ANSWER_LIMIT.inspect} by default). " \
              "Outputs answer (the choice), answered_by and each field by name."

  class << self
    def choices(config) = Array(config[KEY_CHOICES]).map { |choice| choice.to_s.strip }.compact_blank.uniq

    def form_fields(config)
      Array(config[KEY_FIELDS]).select { |field| field.is_a?(Hash) }
                               .map { |field| { FIELD_NAME => field[FIELD_NAME].to_s.strip, FIELD_LABEL => field[FIELD_LABEL].to_s.strip } }
    end

    # Every route an edge out of it may carry.
    def routes_of(config) = [ *(choices(config).presence || [ ROUTE_ANSWERED ]), ROUTE_UNANSWERED ]

    def output_fields(config) = [ OUTPUT_ANSWER, OUTPUT_ANSWERED_BY, *form_fields(config).map { |field| field[FIELD_NAME] } ]

    def problems(step, _workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      found = PEOPLE.problems(config, named, "asks")
      found << "#{named} needs the question it asks." if config[KEY_QUESTION].to_s.strip.empty?
      found << "#{named} asks in at most #{QUESTION_LIMIT.to_fs(:delimited)} characters." if config[KEY_QUESTION].to_s.length > QUESTION_LIMIT
      found.concat(answer_problems(config, named))
    end

    def answer_problems(config, named)
      choices = choices(config)
      fields = form_fields(config)
      names = fields.map { |field| field[FIELD_NAME] }
      found = []
      found << "#{named} needs choices to pick from, a form to fill, or both." if choices.empty? && fields.empty?
      found << "#{named} offers at most #{CHOICE_LIMIT} choices." if choices.size > CHOICE_LIMIT
      found << "#{named} needs each choice named in lowercase letters, numbers and underscores." unless choices.all? { |choice| choice.match?(SolidWorkflow::Definition::STEP_NAME) }
      found << "#{named} cannot call a choice #{ROUTE_UNANSWERED}, since that is the route when nobody answers." if choices.include?(ROUTE_UNANSWERED)
      found << "#{named} asks at most #{FIELD_LIMIT} fields." if fields.size > FIELD_LIMIT
      found << "#{named} needs each field named in lowercase letters, numbers and underscores." unless names.all? { |name| name.match?(SolidWorkflow::Definition::STEP_NAME) }
      found << "#{named} needs what each field asks." if fields.any? { |field| field[FIELD_LABEL].empty? }
      found << "#{named} names a field #{OUTPUT_ANSWER} or #{OUTPUT_ANSWERED_BY}, which it hands on already." if names.intersect?([ OUTPUT_ANSWER, OUTPUT_ANSWERED_BY ])
      found << "#{named} names a field more than once." unless names.uniq.size == names.size
      found
    end

    def describe(config, _workspace) = "Asks #{PEOPLE.whom(config)}: #{config[KEY_QUESTION].to_s.squish}".truncate(200)
  end

  def perform
    asked = QUESTION.find_by(engine_step_id: @step.id)
    members = asked ? [] : people
    answer = await(ASKED) do |name|
      question = QUESTION.create!(
        workspace: workspace, run_step: record, engine_step_id: @step.id, delivery_key: name, question: @config[KEY_QUESTION].to_s.strip,
        details: @config[KEY_DETAILS].to_s.strip.presence, choices: self.class.choices(@config), fields: self.class.form_fields(@config),
        asked_member_ids: members.map(&:id), due_at: Time.current + handed_off_limit
      )
      WorkflowQuestionJob.perform_later(question.id)
    end
    return answer if answer.is_a?(SolidWorkflow::Park)

    answered(answer)
  rescue SolidWorkflow::TimeLimitReached
    unanswered
  end

  def handed_off_limit = ActiveSupport::Duration.build(@step.timeout_seconds || ANSWER_LIMIT.to_i)

  private

  def people
    members = PEOPLE.recipients(workspace, @config, acting: principal)
    raise Refused, "There is nobody to ask: #{PEOPLE.nobody_words(workspace, @config)}." if members.empty?

    members
  end

  def answered(answer)
    choice = answer[QUESTION::ANSWER_CHOICE].presence
    route = choice || ROUTE_ANSWERED
    output = { OUTPUT_ANSWER => choice, OUTPUT_ANSWERED_BY => answer["by"], **answer[QUESTION::ANSWER_FIELDS].to_h }
    SolidWorkflow::Routed.new(output: output, route: route)
  end

  # An answer that won the race with the time limit still counts.
  def unanswered
    question = QUESTION.find_by(engine_step_id: @step.id)
    if question&.expire!
      WorkflowQuestionJob.perform_later(question.id)
    elsif question&.answered?
      return answered(question.answer.merge("by" => question.answered_by&.actor_display_name))
    end
    SolidWorkflow::Routed.new(output: { OUTPUT_ANSWER => nil, OUTPUT_ANSWERED_BY => nil }, route: ROUTE_UNANSWERED)
  end
end
