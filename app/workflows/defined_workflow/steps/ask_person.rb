# Asks a person a question in a direct message and on the run's page, and waits for the answer: one of a few choices,
# each a route out of the step, or a short form whose answers later steps read by name. A choice is the label the
# builder wrote, shown exactly on its button, and the key its route is named by, which Firefight derives from the label
# once and keeps when the label is edited, so connections never break. Anyone it asked can answer, the first answer
# counts, and in a test run the person testing can answer too. A question nobody answers within the step's wait is
# withdrawn and the step takes its unanswered route. Asking reads nothing outside the run, so it needs no grant.
class DefinedWorkflow::Steps::AskPerson < DefinedWorkflow::Steps::Base
  include DefinedWorkflow::Steps::Waiting
  include DefinedWorkflow::Steps::Asking

  kind "ask_person"
  label "Ask a person"
  group GROUP_PEOPLE

  PEOPLE = DefinedWorkflow::Steps::People
  KEY_QUESTION = "question".freeze
  KEY_DETAILS = "details".freeze
  KEY_CHOICES = "choices".freeze
  KEY_FIELDS = "fields".freeze
  CHOICE_KEY = QUESTION::CHOICE_KEY
  CHOICE_LABEL = QUESTION::CHOICE_LABEL
  FIELD_NAME = QUESTION::FIELD_NAME
  FIELD_LABEL = QUESTION::FIELD_LABEL
  OUTPUT_ANSWER = "answer".freeze
  OUTPUT_ANSWERED_BY = "answered_by".freeze
  ROUTE_ANSWERED = "answered".freeze
  ROUTE_UNANSWERED = "unanswered".freeze
  CHOICE_LIMIT = QUESTION::CHOICE_LIMIT
  # Slack draws a button's words up to this many characters.
  CHOICE_LABEL_LIMIT = 75
  # A derived key's length, short enough to read and leaving room for a number that keeps it unique.
  CHOICE_KEY_LENGTH = 40
  FIELD_LIMIT = QUESTION::FIELD_LIMIT
  QUESTION_LIMIT = 1_000

  config_help "#{PEOPLE.help} question (what they are asked, may use references), details (optional, may use references), choices " \
              "(up to #{CHOICE_LIMIT}, each the words on its button as a string, such as \"Roll back now\", or {key, label} to keep a " \
              "choice's key, which names its route and is derived from the label when left out), fields (a short form, up to " \
              "#{FIELD_LIMIT} {name, label}), #{wait_help}. It needs choices, fields or both. Takes the chosen choice's route (its key), " \
              "or answered when it has no choices, and unanswered when nobody answers within its wait. Outputs answer (the chosen " \
              "choice's key), answered_by and each field by name."

  class << self
    # Each choice as { key, label }. A choice saved as a bare word is its own key, read as a label the way it always was,
    # and any other text is a label whose key is derived from it.
    def choices(config)
      given = Array(config[KEY_CHOICES]).filter_map do |choice|
        key, label = choice.is_a?(Hash) ? [ choice[CHOICE_KEY].to_s.strip, choice[CHOICE_LABEL].to_s.strip ] : bare(choice.to_s.strip)
        { CHOICE_KEY => key, CHOICE_LABEL => label } unless key.empty? && label.empty?
      end
      keyed(given)
    end

    def choice_keys(config) = choices(config).map { |choice| choice[CHOICE_KEY] }

    def settled_config(config)
      return config unless config.key?(KEY_CHOICES)

      config.merge(KEY_CHOICES => choices(config))
    end

    def form_fields(config)
      Array(config[KEY_FIELDS]).select { |field| field.is_a?(Hash) }
                               .map { |field| { FIELD_NAME => field[FIELD_NAME].to_s.strip, FIELD_LABEL => field[FIELD_LABEL].to_s.strip } }
    end

    # Every route an edge out of it may carry.
    def routes_of(config) = [ *(choice_keys(config).presence || [ ROUTE_ANSWERED ]), ROUTE_UNANSWERED ]

    # The words a choice's route reads as on the canvas, its label.
    def route_labels(config) = choices(config).to_h { |choice| [ choice[CHOICE_KEY], choice[CHOICE_LABEL] ] }

    def output_fields(config) = [ OUTPUT_ANSWER, OUTPUT_ANSWERED_BY, *form_fields(config).map { |field| field[FIELD_NAME] } ]

    def problems(step, _workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      found = PEOPLE.problems(config, named, "asks")
      found << "#{named} needs the question it asks." if config[KEY_QUESTION].to_s.strip.empty?
      found << "#{named} asks in at most #{QUESTION_LIMIT.to_fs(:delimited)} characters." if config[KEY_QUESTION].to_s.length > QUESTION_LIMIT
      found.concat(wait_problems(config, named))
      found.concat(answer_problems(config, named))
    end

    def answer_problems(config, named)
      choices = choices(config)
      fields = form_fields(config)
      names = fields.map { |field| field[FIELD_NAME] }
      found = []
      found << "#{named} needs choices to pick from, a form to fill, or both." if choices.empty? && fields.empty?
      found.concat(choice_problems(choices, named))
      found << "#{named} asks at most #{FIELD_LIMIT} fields." if fields.size > FIELD_LIMIT
      found << "#{named} needs each field named in lowercase letters, numbers and underscores." unless names.all? { |name| name.match?(SolidWorkflow::Definition::STEP_NAME) }
      found << "#{named} needs what each field asks." if fields.any? { |field| field[FIELD_LABEL].empty? }
      found << "#{named} names a field #{OUTPUT_ANSWER} or #{OUTPUT_ANSWERED_BY}, which it hands on already." if names.intersect?([ OUTPUT_ANSWER, OUTPUT_ANSWERED_BY ])
      found << "#{named} names a field more than once." unless names.uniq.size == names.size
      found
    end

    def choice_problems(choices, named)
      labels = choices.map { |choice| choice[CHOICE_LABEL] }
      keys = choices.map { |choice| choice[CHOICE_KEY] }
      found = []
      found << "#{named} offers at most #{CHOICE_LIMIT} choices." if choices.size > CHOICE_LIMIT
      found << "#{named} needs the words on each choice's button." if labels.any?(&:empty?)
      found << "#{named} keeps each choice to #{CHOICE_LABEL_LIMIT} characters." if labels.any? { |label| label.length > CHOICE_LABEL_LIMIT }
      found << "#{named} offers the same choice more than once." unless labels.map(&:downcase).uniq.size == labels.size
      found << "#{named} keys each choice in lowercase letters, numbers and underscores." unless keys.all? { |key| key.match?(SolidWorkflow::Definition::STEP_NAME) }
      found << "#{named} keys two choices the same." unless keys.uniq.size == keys.size
      found << "#{named} cannot key a choice #{ROUTE_UNANSWERED}, since that is the route when nobody answers." if keys.include?(ROUTE_UNANSWERED)
      found
    end

    def describe(config, _workspace) = "Asks #{PEOPLE.whom(config)}: #{config[KEY_QUESTION].to_s.squish}".truncate(200)

    private

    # A bare word saved before choices had labels, such as roll_back, is its key. Anything else is a label.
    def bare(text)
      text.match?(SolidWorkflow::Definition::STEP_NAME) ? [ text, text.tr("_", " ").upcase_first ] : [ "", text ]
    end

    # Gives each choice without a key one derived from its label, unique within the step and never the route for nobody
    # answering. A key already given is kept as it is.
    def keyed(choices)
      taken = choices.map { |choice| choice[CHOICE_KEY] }.compact_blank.to_set << ROUTE_UNANSWERED
      choices.map do |choice|
        next choice if choice[CHOICE_KEY].present?

        key = unique_key(derived_key(choice[CHOICE_LABEL]), taken)
        taken << key
        choice.merge(CHOICE_KEY => key)
      end
    end

    def derived_key(label)
      slug = I18n.transliterate(label).downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      slug = "choice_#{slug}".delete_suffix("_") unless slug.match?(/\A[a-z]/)
      slug.first(CHOICE_KEY_LENGTH).delete_suffix("_")
    end

    def unique_key(base, taken)
      return base unless taken.include?(base)

      (2..).lazy.map { |number| "#{base}_#{number}" }.find { |key| taken.exclude?(key) }
    end
  end

  private

  def question_attributes
    { kind: QUESTION::KIND_QUESTION, question: @config[KEY_QUESTION].to_s.strip, details: @config[KEY_DETAILS].to_s.strip.presence,
      choices: self.class.choices(@config), fields: self.class.form_fields(@config), asked_member_ids: people.map(&:id) }
  end

  def people
    members = PEOPLE.recipients(workspace, @config, acting: principal)
    raise Refused, "There is nobody to ask: #{PEOPLE.nobody_words(workspace, @config)}." if members.empty?

    members
  end

  def answered(answer)
    choice = answer[QUESTION::ANSWER_CHOICE].presence
    output = { OUTPUT_ANSWER => choice, OUTPUT_ANSWERED_BY => answer["by"], **answer[QUESTION::ANSWER_FIELDS].to_h }
    SolidWorkflow::Routed.new(output: output, route: choice || ROUTE_ANSWERED)
  end

  def nobody_answered = SolidWorkflow::Routed.new(output: { OUTPUT_ANSWER => nil, OUTPUT_ANSWERED_BY => nil }, route: ROUTE_UNANSWERED)
end
