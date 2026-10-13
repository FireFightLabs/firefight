# What the canvas knows about each kind of step, so it never decides one on its own: the group the palette lists it
# under, its name and one line, its icon, how its settings are drawn and what a new one starts with, the fields it hands
# on to later steps, the routes an edge out of it can carry, whether it only reads or changes something, and the
# grants it needs, which say whether the workflow's own identity can run it yet.
#
# The engine's own control steps are registered here with register. A kind the app runs is a class of
# DefinedWorkflow::Steps, which already says its name, group, outputs, whether it changes something and what it needs
# granted, so it is registered with runtime and adds only how the canvas draws it. The palette offers only kinds
# something can run (runnable?), so a step that could never run is never added. Each lambda is given the step as stored
# and a Facts, which answers what the workspace has.
module Workflow::StepKinds
  # The groups of the Steps table, in its order. A kind the app runs names its group on its class (DefinedWorkflow::Steps).
  GROUP_HALON = DefinedWorkflow::Steps::Base::GROUP_HALON
  GROUP_TOOLS = DefinedWorkflow::Steps::Base::GROUP_TOOLS
  GROUP_INCIDENT = "incident".freeze
  GROUP_MESSAGES = DefinedWorkflow::Steps::Base::GROUP_MESSAGES
  GROUP_SANDBOX = "sandbox".freeze
  GROUP_HTTP = "http".freeze
  GROUP_WAITING = DefinedWorkflow::Steps::Base::GROUP_WAITING
  GROUP_PEOPLE = "people".freeze
  GROUP_CONTROL = DefinedWorkflow::Steps::Base::GROUP_CONTROL
  GROUP_BY_HAND = "by_hand".freeze
  GROUPS = [
    GROUP_HALON, GROUP_TOOLS, GROUP_INCIDENT, GROUP_MESSAGES, GROUP_SANDBOX, GROUP_HTTP, GROUP_WAITING, GROUP_PEOPLE,
    GROUP_CONTROL, GROUP_BY_HAND
  ].freeze

  EFFECT_READS = "reads".freeze
  EFFECT_CHANGES = "changes".freeze
  EFFECTS = [ EFFECT_READS, EFFECT_CHANGES ].freeze

  # How the settings sheet draws a kind's config. Fields is the tool field form over the kind's fields, the others are
  # editors of their own for a config a plain form cannot hold.
  EDITOR_FIELDS = "fields".freeze
  EDITOR_BRANCH = "branch".freeze
  EDITOR_DELAY = "delay".freeze
  EDITOR_FOR_EACH = "for_each".freeze
  EDITOR_RUN_WORKFLOW = "run_workflow".freeze
  EDITOR_TOOL = "tool".freeze
  EDITOR_ASK_HALON = "ask_halon".freeze
  EDITOR_WATCH = "watch".freeze
  EDITORS = [ EDITOR_FIELDS, EDITOR_BRANCH, EDITOR_DELAY, EDITOR_FOR_EACH, EDITOR_RUN_WORKFLOW, EDITOR_TOOL, EDITOR_ASK_HALON, EDITOR_WATCH ].freeze

  ICON_BRANCH = "branch".freeze
  ICON_DELAY = "delay".freeze
  ICON_EVENT = "event".freeze
  ICON_LOOP = "loop".freeze
  ICON_JOIN = "join".freeze
  ICON_WORKFLOW = "workflow".freeze
  ICON_TOOL = "tool".freeze
  ICON_HALON = "halon".freeze
  ICON_MESSAGE = "message".freeze
  ICON_CHANNEL = "channel".freeze
  ICON_INCIDENT = "incident".freeze
  ICON_NOTICE = "notice".freeze
  ICON_WATCH = "watch".freeze
  ICON_SKILL = "skill".freeze
  ICON_TERMINAL = "terminal".freeze
  ICON_GLOBE = "globe".freeze
  ICON_PERSON = "person".freeze
  ICON_APPROVAL = "approval".freeze
  ICON_STOP = "stop".freeze
  ICONS = [
    ICON_BRANCH, ICON_DELAY, ICON_EVENT, ICON_LOOP, ICON_JOIN, ICON_WORKFLOW, ICON_TOOL, ICON_HALON, ICON_MESSAGE,
    ICON_CHANNEL, ICON_INCIDENT, ICON_NOTICE, ICON_WATCH, ICON_SKILL, ICON_TERMINAL, ICON_GLOBE, ICON_PERSON,
    ICON_APPROVAL, ICON_STOP
  ].freeze

  # A step that calls one tool Halon can call: a connection's, a capability that answers for anything on the map, or
  # Firefight's own. Its config is the tool's name and the arguments it is called with, as a runbook step's are.
  KIND_CALL_TOOL = "call_tool".freeze
  CONFIG_TOOL = "tool".freeze
  CONFIG_ARGUMENTS = "arguments".freeze

  # The keys of the engine's own steps' config that the canvas's editors write, as the engine reads them
  # (SolidWorkflow::Definition and Condition).
  CONFIG_KEYS = {
    "ROUTES" => "routes", "ROUTE" => "route", "WHEN" => "when", "OTHERWISE" => "otherwise",
    "LEFT" => "left", "OPERATOR" => "operator", "RIGHT" => "right",
    "UNTIL" => "until", "TIME_ZONE" => "time_zone", "AT" => "at",
    "ITEMS" => "items", "CONCURRENCY" => "concurrency",
    "WORKFLOW" => "workflow", "INPUTS" => "inputs"
  }.freeze

  # What a kind's lambdas may ask about the workspace it is drawn for, and the tools Halon can call there by name, each
  # answering name, read_only and action_key. workspace is nil where nothing is known of one, such as a test.
  Facts = Data.define(:workspace, :tools) do
    def initialize(tools: [], workspace: nil) = super

    def tool(name) = tools.find { |each| each.name == name }
  end

  # fields is a list, or a lambda given the Facts for one whose choices are the workspace's own. reach answers what the
  # workflow's own identity needs granted to run the step (DefinedWorkflow::Reach::Needed).
  Kind = Data.define(:key, :group, :label, :description, :icon, :editor, :fields, :defaults, :outputs, :routes, :effect, :reach) do
    def initialize(fields: [], defaults: {}, outputs: ->(_step, _facts) { [] }, routes: ->(_step) { [] },
                   effect: ->(_step, _facts) { EFFECT_READS }, reach: ->(_step, _facts) { [] }, **)
      super
    end

    def fields_for(facts) = fields.respond_to?(:call) ? fields.call(facts) : fields
  end

  # Routes every step can carry an edge on besides its own: the error route, taken when it fails and says so.
  ROUTE_ERROR = DefinedWorkflow::ROUTE_ERROR

  module_function

  def registry = @registry ||= {}

  def register(kind)
    raise ArgumentError, "#{kind.group} is not a group of steps" unless GROUPS.include?(kind.group)
    raise ArgumentError, "#{kind.editor} is not a way to draw a step's settings" unless EDITORS.include?(kind.editor)
    raise ArgumentError, "#{kind.icon} is not an icon a step has" unless ICONS.include?(kind.icon)

    registry[kind.key] = kind
  end

  def all = registry.values

  def find(key) = registry[key.to_s]

  # A kind the engine or the app can run. Only these are offered, so a step added on the canvas can be published.
  def runnable?(key) = DefinedWorkflow::STEP_KINDS.include?(key.to_s) || DefinedWorkflow.action_kinds.map(&:to_s).include?(key.to_s)

  def offered = all.select { |kind| runnable?(kind.key) }

  # Every route an edge out of the step may carry, its own and the error route when it takes it on failure.
  def routes_of(step)
    kind = find(step["kind"])
    own = kind ? kind.routes.call(step) : []
    error = step["on_failure"] == DefinedWorkflow::ON_FAILURE_ERROR_ROUTE ? [ ROUTE_ERROR ] : []
    (own + error).uniq
  end

  def outputs_of(step, facts) = find(step["kind"])&.outputs&.call(step, facts) || []

  def effect_of(step, facts) = find(step["kind"])&.effect&.call(step, facts) || EFFECT_READS

  def reach_of(step, facts) = find(step["kind"])&.reach&.call(step, facts) || []

  # A kind the app runs, described by its class (DefinedWorkflow::Steps::Base), with how the canvas draws it.
  def runtime(klass, icon:, editor:, description:, fields: [], defaults: {}, routes: ->(_step) { [] })
    register(Kind.new(
      key: klass.kind, group: klass.group, label: klass.label, description: description, icon: icon, editor: editor, fields: fields,
      defaults: defaults, routes: routes,
      outputs: ->(step, _facts) { klass.output_fields(step["config"].to_h) },
      effect: ->(step, facts) { facts.workspace && klass.changes?(step["config"].to_h, facts.workspace) ? EFFECT_CHANGES : EFFECT_READS },
      reach: ->(step, facts) { facts.workspace ? klass.reach(step["config"].to_h, facts.workspace).to_a : [] }
    ))
  end

  def field(key, kind, description, options: [], required: false)
    ToolField::Field.new(key: key, kind: kind, options: options, required: required, description: description)
  end

  def fixed_outputs(kind) = ->(_step, _facts) { DefinedWorkflow::OUTPUT_FIELDS.fetch(kind, []) }

  register(Kind.new(
    key: DefinedWorkflow::KIND_BRANCH, group: GROUP_CONTROL, label: "Branch", icon: ICON_BRANCH, editor: EDITOR_BRANCH,
    description: "Takes one path or another on a condition. Steps on a path not taken are skipped.",
    defaults: { "routes" => [ { "route" => "yes", "when" => { "left" => "", "operator" => DefinedWorkflow::CONDITION_EQUALS, "right" => "" } } ],
                "otherwise" => "no" },
    outputs: fixed_outputs(DefinedWorkflow::KIND_BRANCH),
    routes: ->(step) { [ *Array(step.dig("config", "routes")).filter_map { |route| route["route"] if route.is_a?(Hash) }, step.dig("config", "otherwise") ].compact.uniq }
  ))

  register(Kind.new(
    key: DefinedWorkflow::KIND_DELAY, group: GROUP_WAITING, label: "Delay", icon: ICON_DELAY, editor: EDITOR_DELAY,
    description: "Waits a length of time, until a time of day or until a moment.",
    defaults: { "minutes" => 30 }, outputs: fixed_outputs(DefinedWorkflow::KIND_DELAY)
  ))

  register(Kind.new(
    key: DefinedWorkflow::KIND_WAIT_FOR_EVENT, group: GROUP_WAITING, label: "Wait for event", icon: ICON_EVENT, editor: EDITOR_FIELDS,
    description: "Waits until something happens, such as a deploy ending, or until its time limit.",
    fields: [
      field("event", ToolField::KIND_TEXT, "What it waits for, such as deploy.finished.", required: true),
      field("key", ToolField::KIND_TEXT, "Which one, such as the service's name, so it waits for that one only.")
    ],
    defaults: { "event" => "" }, outputs: fixed_outputs(DefinedWorkflow::KIND_WAIT_FOR_EVENT),
    routes: ->(_step) { [ DefinedWorkflow::ROUTE_RECEIVED, DefinedWorkflow::ROUTE_TIMED_OUT ] }
  ))

  register(Kind.new(
    key: DefinedWorkflow::KIND_FOR_EACH, group: GROUP_CONTROL, label: "For each", icon: ICON_LOOP, editor: EDITOR_FOR_EACH,
    description: "Runs the steps inside it once for each item of a list, such as services or hosts.",
    defaults: { "items" => "", "concurrency" => 1, "steps" => [], "edges" => [] }, outputs: fixed_outputs(DefinedWorkflow::KIND_FOR_EACH)
  ))

  register(Kind.new(
    key: DefinedWorkflow::KIND_JOIN, group: GROUP_CONTROL, label: "Join", icon: ICON_JOIN, editor: EDITOR_FIELDS,
    description: "Waits for every path into it, or the first one, before going on.",
    fields: [
      field("mode", ToolField::KIND_SELECT, "Wait for all of the paths into it, or go on with the first.",
            options: DefinedWorkflow::JOIN_MODES, required: true)
    ],
    defaults: { "mode" => DefinedWorkflow::JOIN_ALL }, outputs: fixed_outputs(DefinedWorkflow::KIND_JOIN)
  ))

  register(Kind.new(
    key: DefinedWorkflow::KIND_RUN_WORKFLOW, group: GROUP_CONTROL, label: "Run workflow", icon: ICON_WORKFLOW, editor: EDITOR_RUN_WORKFLOW,
    description: "Runs another workflow with inputs and takes what it hands back.",
    defaults: { "workflow" => "", "inputs" => {} }
  ))

  runtime(DefinedWorkflow::Steps::CallTool, icon: ICON_TOOL, editor: EDITOR_TOOL,
          description: "Calls any tool Halon can call, a connection's, one that answers for anything on the map, or Firefight's own.",
          defaults: { CONFIG_TOOL => "", CONFIG_ARGUMENTS => {} })

  runtime(DefinedWorkflow::Steps::AskHalon, icon: ICON_HALON, editor: EDITOR_ASK_HALON,
          description: "Asks Halon to judge what earlier steps found and answer with a verdict, a summary and any field you name.",
          defaults: { DefinedWorkflow::Steps::AskHalon::KEY_QUESTION => "", DefinedWorkflow::Steps::AskHalon::KEY_DATA => "" })

  runtime(DefinedWorkflow::Steps::RunSkill, icon: ICON_SKILL, editor: EDITOR_FIELDS,
          description: "Has Halon follow one of its skills, such as the probing scan, and report what it found. It only reads.",
          fields: lambda { |facts|
            skills = facts.workspace ? Chat::Skill.available_to(facts.workspace).map(&:name).sort : []
            [ field(DefinedWorkflow::Steps::RunSkill::KEY_SKILL, ToolField::KIND_SELECT, "The skill Halon follows.", options: skills, required: true),
              field(DefinedWorkflow::Steps::RunSkill::KEY_FOCUS, ToolField::KIND_PARAGRAPH, "What to look at, such as one service or the last hour.") ]
          },
          defaults: { DefinedWorkflow::Steps::RunSkill::KEY_SKILL => "", DefinedWorkflow::Steps::RunSkill::KEY_FOCUS => "" })

  runtime(DefinedWorkflow::Steps::Watch, icon: ICON_WATCH, editor: EDITOR_WATCH,
          description: "Watches something for a while, such as an error rate after a change, and goes on when it settles, fails or runs out of time.",
          defaults: { Chat::Watch::SPEC_KEYS[:title] => "", Chat::Watch::SPEC_KEYS[:steps] => [] },
          routes: ->(_step) { DefinedWorkflow::Steps::Watch::ROUTES })

  runtime(DefinedWorkflow::Steps::PostToChannel, icon: ICON_CHANNEL, editor: EDITOR_FIELDS,
          description: "Posts a message as Firefight in a channel, with what earlier steps found in it.",
          fields: [
            field(DefinedWorkflow::Steps::PostToChannel::KEY_CHANNEL, ToolField::KIND_TEXT, "The channel it posts in, such as #ops."),
            field(DefinedWorkflow::Steps::PostToChannel::KEY_REPLY, ToolField::KIND_TOGGLE, "Post back where the workflow was asked for instead, when Halon made it from a chat."),
            field(DefinedWorkflow::Steps::PostToChannel::KEY_MESSAGE, ToolField::KIND_PARAGRAPH, "What it posts, in Markdown.", required: true)
          ],
          defaults: { DefinedWorkflow::Steps::PostToChannel::KEY_CHANNEL => "", DefinedWorkflow::Steps::PostToChannel::KEY_MESSAGE => "" })

  runtime(DefinedWorkflow::Steps::RaiseNotice, icon: ICON_NOTICE, editor: EDITOR_FIELDS,
          description: "Raises a monitoring notice with Halon, said once and again only when it gets worse.",
          fields: [
            field(DefinedWorkflow::Steps::RaiseNotice::KEY_SIGNAL, ToolField::KIND_SELECT, "What kind of problem it is.", options: Investigation::Notice::SIGNALS, required: true),
            field(DefinedWorkflow::Steps::RaiseNotice::KEY_TOPIC, ToolField::KIND_TEXT, "What it is about, the same each time for the same problem.", required: true),
            field(DefinedWorkflow::Steps::RaiseNotice::KEY_SUMMARY, ToolField::KIND_PARAGRAPH, "What the notice says.", required: true),
            field(DefinedWorkflow::Steps::RaiseNotice::KEY_SEVERITY, ToolField::KIND_SELECT, "How bad it is.", options: Investigation::Notice::SEVERITIES),
            field(DefinedWorkflow::Steps::RaiseNotice::KEY_DUE_ON, ToolField::KIND_TEXT, "When it must be dealt with by, as YYYY-MM-DD."),
            field(DefinedWorkflow::Steps::RaiseNotice::KEY_RESOURCE, ToolField::KIND_RESOURCE, "What on the map it is about.")
          ],
          defaults: { DefinedWorkflow::Steps::RaiseNotice::KEY_SIGNAL => Investigation::Notice::SIGNAL_OTHER,
                      DefinedWorkflow::Steps::RaiseNotice::KEY_SEVERITY => Investigation::Notice::SEVERITY_MEDIUM })
end
