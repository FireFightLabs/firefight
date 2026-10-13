# A workflow written out whole, as Halon or an outside agent gives it: a name, a trigger, its steps by name and the
# connections between them, or a template from the library with its answers. It becomes a draft one attributed edit at a
# time, and one that could not be published is refused with what is wrong, so whoever wrote it fixes it first.
module Workflow::Authoring
  class Refused < StandardError; end

  KEY_NAME = "name".freeze
  KEY_DESCRIPTION = "description".freeze
  KEY_TRIGGER = "trigger".freeze
  KEY_STEPS = "steps".freeze
  KEY_EDGES = "edges".freeze
  KEY_TEMPLATE = "template".freeze
  KEY_PARAMS = "params".freeze
  KEY_ALL_CLEAR = "all_clear".freeze
  # A once at trigger's time as minutes from now, worked out when it is written.
  KEY_IN_MINUTES = "in_minutes".freeze
  STEP_SETTINGS = %w[on_failure timeout_seconds retry].freeze
  # A once at trigger reaches at most this far ahead, in minutes.
  LONGEST_WAIT = Workflow::Trigger::Schedule::LATEST.in_minutes.to_i

  module_function

  # The workflow as an agent writes it, shared by Halon's create_workflow and the MCP tool, so both take one shape.
  def schema
    kinds = DefinedWorkflow::Steps.kinds.map { |kind| "#{kind.kind}: #{kind.config_help}" }.join(" ")
    {
      "type" => "object",
      "properties" => {
        KEY_NAME => { "type" => "string", "description" => "What it is called, such as Check web after the deploy" },
        KEY_DESCRIPTION => { "type" => "string", "description" => "What it does, in a sentence (optional)" },
        KEY_TEMPLATE => { "type" => "string", "enum" => Workflow::Library::KEYS,
                          "description" => "A workflow from the library instead of steps: check_later (params resource, in_minutes or at, " \
                                           "channel or reply_in_chat) or probing_scan (params at, days, time_zone)" },
        KEY_PARAMS => { "type" => "object", "description" => "The template's answers" },
        KEY_TRIGGER => {
          "type" => "object",
          "description" => "What starts it. kind manual (by hand only), schedule, once_at, called or one of the kinds below. A schedule has repeat minutes or hours with every, " \
                           "days with at (09:00) and days (0 Sunday to 6 Saturday), or monthly with week_of_month (1 to 4 or last), weekday and at. " \
                           "once_at has at (a local date and time such as 2026-10-13T14:30) or in_minutes. time_zone defaults to the person's own. " \
                           "inputs are questions a run by hand asks, each {key, question, default}. Every workflow can also be run by hand. " \
                           "Kinds that something happening starts, each read by later steps as {{trigger.<path>}}: #{Workflow::TriggerKinds.help}"
        },
        KEY_STEPS => { "type" => "array", "items" => { "type" => "object" },
                       "description" => "Each step {name, kind, config, on_failure (stop, continue or error_route, optional)}. A step reads earlier " \
                                        "steps' outputs with {{steps.<name>.<field>}} and inputs with {{inputs.<key>}}. Kinds and their config: #{kinds}" },
        KEY_EDGES => { "type" => "array", "items" => { "type" => "object" },
                       "description" => "Which step runs after which, each {from, to, route (optional, a branch's route or error)} by step name. " \
                                        "A step with no edge into it runs first." },
        KEY_ALL_CLEAR => { "type" => "boolean", "description" => "Post a one line all clear when a run finds nothing to raise or post (optional)" }
      },
      "required" => []
    }
  end

  # spec is the whole workflow with string keys. time_zone is the writer's own, used where the spec gives none.
  def create!(workspace:, spec:, by:, halon: false, reason: nil, time_zone: nil, origin_conversation: nil)
    spec = spec.to_h.deep_stringify_keys
    zone = time_zone.presence || "UTC"
    workflow = Workflow.transaction do
      made = spec[KEY_TEMPLATE].present? ? from_template(workspace, spec, by, halon, reason, zone, origin_conversation) : written(workspace, spec, by, halon, reason, zone, origin_conversation)
      problems = made.draft.problems
      raise Refused, "It cannot be published as written. #{problems.join(' ')}" if problems.any?

      made
    end
    workflow.ensure_agent!
    workflow
  rescue Workflow::Library::Refused, Workflow::Edit::Refused => refused
    raise Refused, refused.message
  rescue ActiveRecord::RecordInvalid => invalid
    raise Refused, invalid.record.errors.full_messages.to_sentence
  end

  # What a workflow as written would be, without making anything: when it runs, each step as kind and words, what its
  # own identity would need granted, and the first thing that stops it being published. The confirmation shows it.
  Preview = Data.define(:problem, :when, :steps, :reach)

  def preview(workspace:, spec:, time_zone: nil)
    spec = spec.to_h.deep_stringify_keys
    content = content_of(workspace, spec, time_zone.presence || "UTC")
    version = Workflow::Version.new(workflow: Workflow.new(workspace: workspace, name: content[:name]), trigger: content[:trigger],
                                    steps: content[:steps], edges: content[:edges], outputs: {})
    problem = version.problems.first
    kinds = version.step_kinds
    steps = Workflow::Version.all_steps(version.steps).map do |step|
      kind = kinds[step["id"]]
      [ kind&.label || step["kind"].to_s.humanize, [ step["name"], kind&.describe(step["config"].to_h, workspace).presence ].compact.join(": ") ]
    end
    Preview.new(problem: problem && "It cannot be published as written. #{problem}", when: when_words(content[:trigger]), steps: steps,
                reach: version.reach.map { |needed| needed.label.downcase_first })
  rescue Refused, Workflow::Library::Refused => refused
    Preview.new(problem: refused.message, when: nil, steps: [], reach: [])
  end

  # When it would run, its moments written so each reader sees them in their own time zone (Chat::TimeToken): a one off
  # at its moment, a schedule in its own words and its next moment.
  def when_words(trigger)
    next_at = Workflow::Trigger::Schedule.timed?(trigger) && Workflow::Trigger::Schedule.next_after(trigger, Time.current)
    return Workflow::Trigger.words(trigger) unless next_at
    return "Once at #{Chat::TimeToken.for(next_at)}" if trigger[Workflow::Trigger::KEY_KIND] == Workflow::Trigger::KIND_ONCE_AT

    "#{Workflow::Trigger.words(trigger)}, next at #{Chat::TimeToken.for(next_at)}"
  end

  # The name, trigger, steps and connections a spec writes, from a template or as written.
  def content_of(workspace, spec, zone)
    if spec[KEY_TEMPLATE].present?
      found = Workflow::Library.template(spec[KEY_TEMPLATE])
      params = template_params(spec, zone)
      return Workflow::Library.content_for(workspace, found.key, params).merge(name: spec[KEY_NAME].presence || Workflow::Library.default_name(found, params))
    end

    steps = Array(spec[KEY_STEPS])
    raise Refused, "A workflow needs at least one step." if steps.empty?

    { name: spec[KEY_NAME], trigger: trigger_from(spec[KEY_TRIGGER], zone), steps: steps.map { |step| step_from(step) }, edges: Array(spec[KEY_EDGES]).map { |each| edge_from(each) } }
  end

  def template_params(spec, zone)
    params = spec[KEY_PARAMS].to_h.deep_stringify_keys
    params[Workflow::Library::PARAM_TIME_ZONE] = params[Workflow::Library::PARAM_TIME_ZONE].presence || zone
    params[Workflow::Library::PARAM_AT] = local_after(params.delete(KEY_IN_MINUTES), params[Workflow::Library::PARAM_TIME_ZONE]) if params.key?(KEY_IN_MINUTES)
    params
  end

  def from_template(workspace, spec, by, halon, reason, zone, origin_conversation)
    params = template_params(spec, zone)
    made = Workflow::Library.create!(workspace: workspace, key: spec[KEY_TEMPLATE], params: params, by: by, name: spec[KEY_NAME], halon: halon,
                                     reason: reason, origin_conversation: origin_conversation)
    made.update!(all_clear: true) if ActiveModel::Type::Boolean.new.cast(spec[KEY_ALL_CLEAR])
    made
  end

  def written(workspace, spec, by, halon, reason, zone, origin_conversation)
    content = content_of(workspace, spec, zone)
    made = Workflow.create!(workspace: workspace, name: content[:name], description: spec[KEY_DESCRIPTION].presence, created_by: by,
                            all_clear: ActiveModel::Type::Boolean.new.cast(spec[KEY_ALL_CLEAR]) || false, origin_conversation: origin_conversation)
    edit = ->(operation, payload) { made.edit!(operation: operation, payload: payload, by: by, halon: halon, reason: reason || "Written as asked.") }
    edit.call(Workflow::Edit::OPERATION_CHANGE_TRIGGER, { trigger: content[:trigger] })
    content[:steps].each { |step| edit.call(Workflow::Edit::OPERATION_ADD_STEP, { step: step }) }
    content[:edges].each { |connection| edit.call(Workflow::Edit::OPERATION_CONNECT, connection) }
    made
  end

  def trigger_from(given, zone)
    trigger = given.to_h.deep_stringify_keys
    trigger[Workflow::Trigger::KEY_KIND] = trigger[Workflow::Trigger::KEY_KIND].presence || Workflow::Trigger::KIND_MANUAL
    trigger[Workflow::Trigger::KEY_INPUTS] = Array(trigger[Workflow::Trigger::KEY_INPUTS])
    return trigger unless Workflow::Trigger::Schedule.timed?(trigger)

    trigger[Workflow::Trigger::Schedule::KEY_TIME_ZONE] = trigger[Workflow::Trigger::Schedule::KEY_TIME_ZONE].presence || zone
    minutes = trigger.delete(KEY_IN_MINUTES)
    trigger[Workflow::Trigger::Schedule::KEY_AT] = local_after(minutes, trigger[Workflow::Trigger::Schedule::KEY_TIME_ZONE]) if minutes.present?
    trigger
  end

  # A time some minutes from now, on the trigger's own clock, as a once at trigger keeps it.
  def local_after(minutes, zone_name)
    count = minutes.to_i
    raise Refused, "Say in how many minutes, between 1 and #{LONGEST_WAIT}." unless count.between?(1, LONGEST_WAIT)

    zone = ActiveSupport::TimeZone[zone_name.to_s] || raise(Refused, "#{zone_name} is not a time zone Firefight knows.")
    at = (Time.current + count.minutes).in_time_zone(zone)
    at = at.change(sec: 0) + (at.sec.positive? || at.usec.positive? ? 1.minute : 0)
    at.strftime("%Y-%m-%dT%H:%M")
  end

  def step_from(given)
    step = given.to_h.deep_stringify_keys
    name = step["name"].to_s
    raise Refused, "Each step needs a name of lowercase letters, numbers and underscores, such as check_logs." unless name.match?(DefinedWorkflow::STEP_NAME)

    { "id" => id_of(name), "name" => name, "kind" => step["kind"].to_s, "config" => step["config"].to_h }.merge(step.slice(*STEP_SETTINGS))
  end

  def edge_from(given)
    edge = given.to_h.deep_stringify_keys
    { "from" => id_of(edge["from"]), "to" => id_of(edge["to"]), "route" => edge["route"].presence }.compact
  end

  def id_of(name) = "step_#{name}"
end
