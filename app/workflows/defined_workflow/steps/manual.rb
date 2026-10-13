# Pauses the run and gives a person a task: a named member or an incident's lead, in a direct message, or anyone, in the
# incident's channel or the channel of the team that owns the workflow. It shows on the run's page too, and whoever
# may presses Done there or in chat, writing the note it collects when it asks for one, such as a ticket number, which
# later steps read. In a test run the person testing can mark it done. A task nobody marks done within the step's wait
# is withdrawn and the step takes its not done route. It changes nothing itself, so it needs no grant.
class DefinedWorkflow::Steps::Manual < DefinedWorkflow::Steps::Base
  include DefinedWorkflow::Steps::Waiting
  include DefinedWorkflow::Steps::Asking

  kind "manual"
  label "Manual step"
  group GROUP_PEOPLE

  PEOPLE = DefinedWorkflow::Steps::People
  KEY_TASK = "task".freeze
  KEY_TO = PEOPLE::KEY_TO
  KEY_PERSON = PEOPLE::KEY_PERSON
  KEY_INCIDENT = PEOPLE::KEY_INCIDENT
  KEY_NOTE = "note".freeze
  TO_PERSON = PEOPLE::TO_PERSON
  TO_LEAD = PEOPLE::TO_LEAD
  TO_ANYONE = "anyone".freeze
  TO = [ TO_PERSON, TO_LEAD, TO_ANYONE ].freeze
  # Who an incident is named for, its lead doing the task or a task for anyone posted in its channel.
  IN_INCIDENT = [ TO_LEAD, TO_ANYONE ].freeze
  OUTPUT_DONE_BY = "done_by".freeze
  OUTPUT_NOTE = "note".freeze
  ROUTE_DONE = "done".freeze
  ROUTE_NOT_DONE = "not_done".freeze
  ROUTES = [ ROUTE_DONE, ROUTE_NOT_DONE ].freeze
  TASK_LIMIT = 1_000
  NOTE_LABEL_LIMIT = 75

  config_help "task (what needs doing, may use references), to (#{TO.join(', ')}), person (an email, for person), incident (its " \
              "identifier, for lead, and for anyone to post it in that incident's channel rather than the owning team's), note " \
              "(optional, what to write when it is done, such as \"Ticket number\", handed on as note), #{wait_help}. Takes done " \
              "when someone marks it done and not_done when nobody does within its wait. Outputs done_by and note."

  class << self
    def output_fields(config) = [ OUTPUT_DONE_BY, *(OUTPUT_NOTE if note_label(config)) ]

    def note_label(config) = config[KEY_NOTE].to_s.strip.presence

    def problems(step, _workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      found = []
      found << "#{named} needs the task it gives." if config[KEY_TASK].to_s.strip.empty?
      found << "#{named} gives a task in at most #{TASK_LIMIT.to_fs(:delimited)} characters." if config[KEY_TASK].to_s.length > TASK_LIMIT
      found.concat(who_problems(config, named))
      found << "#{named} keeps its note's name to #{NOTE_LABEL_LIMIT} characters." if note_label(config).to_s.length > NOTE_LABEL_LIMIT
      found.concat(wait_problems(config, named))
    end

    def who_problems(config, named)
      to = config[KEY_TO].to_s
      return [ "#{named} needs who it is given to, one of #{TO.join(', ')}." ] unless TO.include?(to)
      return [ "#{named} needs the person it is given to, by email." ] if to == TO_PERSON && config[KEY_PERSON].to_s.strip.empty?
      return [ "#{named} needs the incident whose lead it is given to." ] if to == TO_LEAD && config[KEY_INCIDENT].to_s.strip.empty?

      []
    end

    def describe(config, _workspace)
      whom = config[KEY_TO] == TO_ANYONE ? "anyone" : PEOPLE.whom(config)
      "Gives #{whom}: #{config[KEY_TASK].to_s.squish}".truncate(200)
    end
  end

  private

  def question_attributes
    anyone = @config[KEY_TO] == TO_ANYONE
    note = self.class.note_label(@config)
    { kind: QUESTION::KIND_TASK, question: @config[KEY_TASK].to_s.strip, choices: [],
      fields: note ? [ { QUESTION::FIELD_NAME => OUTPUT_NOTE, QUESTION::FIELD_LABEL => note } ] : [],
      asked_member_ids: anyone ? [] : assignees.map(&:id), open_to_anyone: anyone,
      channel_id: (@run.asking_channel_id(PEOPLE.incident(workspace, @config)) if anyone) }
  end

  def assignees
    members = PEOPLE.recipients(workspace, @config, acting: principal)
    raise Refused, "There is nobody to give it to: #{PEOPLE.nobody_words(workspace, @config)}." if members.empty?

    members
  end

  def answered(answer)
    note = answer[QUESTION::ANSWER_FIELDS].to_h[OUTPUT_NOTE]
    output = { OUTPUT_DONE_BY => answer["by"], **(self.class.note_label(@config) ? { OUTPUT_NOTE => note } : {}) }
    SolidWorkflow::Routed.new(output: output, route: ROUTE_DONE)
  end

  def nobody_answered
    output = { OUTPUT_DONE_BY => nil, **(self.class.note_label(@config) ? { OUTPUT_NOTE => nil } : {}) }
    SolidWorkflow::Routed.new(output: output, route: ROUTE_NOT_DONE)
  end
end
