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
  GROUP_INCIDENT = DefinedWorkflow::Steps::Base::GROUP_INCIDENT
  GROUP_MESSAGES = DefinedWorkflow::Steps::Base::GROUP_MESSAGES
  GROUP_SANDBOX = DefinedWorkflow::Steps::Base::GROUP_SANDBOX
  GROUP_HTTP = DefinedWorkflow::Steps::Base::GROUP_HTTP
  GROUP_WAITING = DefinedWorkflow::Steps::Base::GROUP_WAITING
  GROUP_PEOPLE = DefinedWorkflow::Steps::Base::GROUP_PEOPLE
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
  # The tool editor, offering only the tools of connected status pages that change something.
  EDITOR_STATUS_PAGE = "status_page".freeze
  # The browser's path: an address, screen sizes, a login, steps and the one that may send.
  EDITOR_BROWSER = "browser".freeze
  # Names and values for later steps.
  EDITOR_SET_DATA = "set_data".freeze
  # Who is asked, the question, its choices and its short form.
  EDITOR_ASK_PERSON = "ask_person".freeze
  # Who approves, the question, and the incident whose conditions are read again.
  EDITOR_APPROVAL = "approval".freeze
  # The field form for a task and who it is given to, with how long it waits.
  EDITOR_MANUAL = "manual".freeze
  EDITORS = [
    EDITOR_FIELDS, EDITOR_BRANCH, EDITOR_DELAY, EDITOR_FOR_EACH, EDITOR_RUN_WORKFLOW, EDITOR_TOOL, EDITOR_ASK_HALON, EDITOR_WATCH, EDITOR_STATUS_PAGE, EDITOR_BROWSER,
    EDITOR_SET_DATA, EDITOR_ASK_PERSON, EDITOR_APPROVAL, EDITOR_MANUAL
  ].freeze

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
  ICON_INVESTIGATE = "investigate".freeze
  ICON_CLASSIFY = "classify".freeze
  ICON_PAGE = "page".freeze
  ICON_FOLLOW_UP = "follow_up".freeze
  ICON_STATUS_PAGE = "status_page".freeze
  ICON_SCRIPT = "script".freeze
  ICON_BROWSER = "browser".freeze
  ICON_WEBHOOK = "webhook".freeze
  ICON_DATA = "data".freeze
  ICON_TASK = "task".freeze
  ICONS = [
    ICON_BRANCH, ICON_DELAY, ICON_EVENT, ICON_LOOP, ICON_JOIN, ICON_WORKFLOW, ICON_TOOL, ICON_HALON, ICON_MESSAGE,
    ICON_CHANNEL, ICON_INCIDENT, ICON_NOTICE, ICON_WATCH, ICON_SKILL, ICON_TERMINAL, ICON_GLOBE, ICON_PERSON,
    ICON_APPROVAL, ICON_STOP, ICON_INVESTIGATE, ICON_CLASSIFY, ICON_PAGE, ICON_FOLLOW_UP, ICON_STATUS_PAGE, ICON_SCRIPT, ICON_BROWSER, ICON_WEBHOOK,
    ICON_DATA, ICON_TASK
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
  # workflow's own identity needs granted to run the step (DefinedWorkflow::Reach::Needed). conditions are the fields an
  # incident's conditions read, for a step that reads them (Workflow::TriggerKinds::ConditionField).
  # route_labels are the words a route reads as where they are not its own, such as a choice's label for its key, and
  # waits says the step waits on a person for as long as its settings say.
  Kind = Data.define(:key, :group, :label, :description, :icon, :editor, :fields, :defaults, :outputs, :routes, :effect, :reach, :conditions,
                     :route_labels, :waits) do
    def initialize(fields: [], defaults: {}, outputs: ->(_step, _facts) { [] }, routes: ->(_step) { [] },
                   effect: ->(_step, _facts) { EFFECT_READS }, reach: ->(_step, _facts) { [] }, conditions: ->(_facts) { [] },
                   route_labels: ->(_step) { {} }, waits: false, **)
      super
    end

    def fields_for(facts) = fields.respond_to?(:call) ? fields.call(facts) : fields

    def conditions_for(facts) = conditions.call(facts)
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

  def route_labels_of(step) = find(step["kind"])&.route_labels&.call(step) || {}

  def waits?(step) = find(step["kind"])&.waits || false

  # A kind the app runs, described by its class (DefinedWorkflow::Steps::Base), with how the canvas draws it.
  def runtime(klass, icon:, editor:, description:, fields: [], defaults: {}, routes: ->(_step) { [] }, conditions: ->(_facts) { [] },
              route_labels: ->(_step) { {} })
    register(Kind.new(
      key: klass.kind, group: klass.group, label: klass.label, description: description, icon: icon, editor: editor, fields: fields,
      defaults: defaults, routes: routes, conditions: conditions, route_labels: route_labels, waits: klass.waits?,
      outputs: ->(step, _facts) { klass.output_fields(step["config"].to_h) },
      effect: ->(step, facts) { facts.workspace && klass.changes?(step["config"].to_h, facts.workspace) ? EFFECT_CHANGES : EFFECT_READS },
      reach: ->(step, facts) { facts.workspace ? klass.reach(step["config"].to_h, facts.workspace).to_a : [] }
    ))
  end

  def field(key, kind, description, options: [], required: false, shown_when: nil)
    ToolField::Field.new(key: key, kind: kind, options: options, required: required, description: description, shown_when: shown_when)
  end

  # The workspace's own values for a choice, by slug, or none where nothing is known of a workspace.
  def slugs(facts) = facts.workspace ? yield(facts.workspace).pluck(:slug) : []

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

  register(Kind.new(
    key: DefinedWorkflow::KIND_STOP, group: GROUP_CONTROL, label: "Stop", icon: ICON_STOP, editor: EDITOR_FIELDS,
    description: "Ends the run here, as succeeded or as failed with a reason. Steps that have not run yet are left.",
    fields: [
      field(DefinedWorkflow::STOP_OUTCOME, ToolField::KIND_SELECT, "How the run ends.", options: DefinedWorkflow::STOP_OUTCOMES, required: true),
      field(DefinedWorkflow::STOP_REASON, ToolField::KIND_TEXT, "Why it ends, shown on the run. A run that fails needs one.")
    ],
    defaults: { DefinedWorkflow::STOP_OUTCOME => DefinedWorkflow::STOP_SUCCEEDED, DefinedWorkflow::STOP_REASON => "" }, outputs: fixed_outputs(DefinedWorkflow::KIND_STOP)
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

  INVESTIGATE = DefinedWorkflow::Steps::Investigate
  runtime(INVESTIGATE, icon: ICON_INVESTIGATE, editor: EDITOR_FIELDS,
          description: "Starts a Halon investigation of an incident or a problem and waits for what it finds and how sure it is.",
          fields: [
            field(INVESTIGATE::KEY_INCIDENT, ToolField::KIND_TEXT, "The incident it investigates, such as {{trigger.incident.identifier}}."),
            field(INVESTIGATE::KEY_SYMPTOM, ToolField::KIND_PARAGRAPH, "What is wrong, needed when there is no incident."),
            field(INVESTIGATE::KEY_NAMES, ToolField::KIND_LIST, "Services, apps or repositories it is about.")
          ],
          defaults: { INVESTIGATE::KEY_INCIDENT => "{{trigger.incident.identifier}}" })

  CLASSIFY = DefinedWorkflow::Steps::Classify
  runtime(CLASSIFY, icon: ICON_CLASSIFY, editor: EDITOR_FIELDS,
          description: "Has Halon sort what it is given into one of the routes you name, each a path out of the step.",
          fields: [
            field(CLASSIFY::KEY_DATA, ToolField::KIND_PARAGRAPH, "What Halon sorts, usually an earlier value.", required: true),
            field(CLASSIFY::KEY_ROUTES, ToolField::KIND_LIST, "The routes it sorts into, such as noise, outage, watch.", required: true),
            field(CLASSIFY::KEY_GUIDANCE, ToolField::KIND_PARAGRAPH, "How to tell them apart."),
            field(CLASSIFY::KEY_OTHERWISE, ToolField::KIND_TEXT, "The route taken when none fits.")
          ],
          defaults: { CLASSIFY::KEY_DATA => "", CLASSIFY::KEY_ROUTES => [], CLASSIFY::KEY_OTHERWISE => CLASSIFY::DEFAULT_OTHERWISE },
          routes: ->(step) { CLASSIFY.all_routes(step["config"].to_h) })

  OPEN = DefinedWorkflow::Steps::OpenIncident
  runtime(OPEN, icon: ICON_INCIDENT, editor: EDITOR_FIELDS,
          description: "Declares an incident through the workspace's declare form, as /ff declare does.",
          fields: lambda { |facts|
            [ field(OPEN::KEY_NAME, ToolField::KIND_TEXT, "What the incident is called.", required: true),
              field(OPEN::KEY_SUMMARY, ToolField::KIND_PARAGRAPH, "What is happening."),
              field(OPEN::KEY_SEVERITY, ToolField::KIND_SELECT, "How bad it is.", options: slugs(facts) { |workspace| workspace.incident_severities.active.by_rank }),
              field(OPEN::KEY_TYPE, ToolField::KIND_SELECT, "What kind of incident it is.", options: slugs(facts) { |workspace| workspace.incident_types.active.ordered }),
              field(DefinedWorkflow::Steps::Base::KEY_UNDO, ToolField::KIND_TEXT, "How a person puts it back, such as cancelling the incident.", required: true) ]
          },
          defaults: { OPEN::KEY_NAME => "", DefinedWorkflow::Steps::Base::KEY_UNDO => "Cancel the incident." })

  UPDATE = DefinedWorkflow::Steps::UpdateIncident
  runtime(UPDATE, icon: ICON_INCIDENT, editor: EDITOR_FIELDS,
          description: "Changes one thing about an incident: its status, severity, type, fields, lead or a role, who is invited, or a runbook.",
          fields: lambda { |facts|
            only = ->(*changes) { { UPDATE::KEY_CHANGE => changes } }
            [ field(UPDATE::KEY_INCIDENT, ToolField::KIND_TEXT, "The incident it changes, such as {{trigger.incident.identifier}}.", required: true),
              field(UPDATE::KEY_CHANGE, ToolField::KIND_SELECT, "What it changes.", options: UPDATE::CHANGES, required: true),
              field(UPDATE::KEY_STATUS, ToolField::KIND_SELECT, "The status it sets.", options: slugs(facts) { |workspace| workspace.incident_statuses.active.ordered },
                    required: true, shown_when: only.call(UPDATE::CHANGE_STATUS)),
              field(UPDATE::KEY_SEVERITY, ToolField::KIND_SELECT, "The severity it sets.", options: slugs(facts) { |workspace| workspace.incident_severities.active.by_rank },
                    required: true, shown_when: only.call(UPDATE::CHANGE_SEVERITY)),
              field(UPDATE::KEY_TYPE, ToolField::KIND_SELECT, "The type it sets.", options: slugs(facts) { |workspace| workspace.incident_types.active.ordered },
                    required: true, shown_when: only.call(UPDATE::CHANGE_TYPE)),
              field(UPDATE::KEY_ROLE, ToolField::KIND_SELECT, "The role it fills.", options: slugs(facts) { |workspace| workspace.incident_roles.active.ordered },
                    required: true, shown_when: only.call(UPDATE::CHANGE_ROLE)),
              field(UPDATE::KEY_MEMBER, ToolField::KIND_TEXT, "Who, by email.", required: true, shown_when: only.call(UPDATE::CHANGE_LEAD, UPDATE::CHANGE_ROLE)),
              field(UPDATE::KEY_MEMBERS, ToolField::KIND_LIST, "Who it invites, by email.", required: true, shown_when: only.call(UPDATE::CHANGE_INVITE)),
              field(UPDATE::KEY_RUNBOOK, ToolField::KIND_SELECT, "The runbook it attaches.", options: slugs(facts) { |workspace| workspace.runbooks },
                    required: true, shown_when: only.call(UPDATE::CHANGE_RUNBOOK)),
              field(UPDATE::KEY_MESSAGE, ToolField::KIND_PARAGRAPH, "Words posted with the change, in Markdown.", shown_when: only.call(*UPDATE::FORM_CHANGES)),
              field(DefinedWorkflow::Steps::Base::KEY_UNDO, ToolField::KIND_TEXT, "How a person puts it back, such as setting it as it was.", required: true) ]
          },
          defaults: { UPDATE::KEY_INCIDENT => "{{trigger.incident.identifier}}", UPDATE::KEY_CHANGE => UPDATE::CHANGE_SEVERITY })

  POST_UPDATE = DefinedWorkflow::Steps::PostIncidentUpdate
  runtime(POST_UPDATE, icon: ICON_INCIDENT, editor: EDITOR_FIELDS,
          description: "Posts an update on an incident, once or again every few minutes while it is live.",
          fields: [
            field(POST_UPDATE::KEY_INCIDENT, ToolField::KIND_TEXT, "The incident it posts on.", required: true),
            field(POST_UPDATE::KEY_MESSAGE, ToolField::KIND_PARAGRAPH, "What it posts, in Markdown.", required: true),
            field(POST_UPDATE::KEY_EVERY, ToolField::KIND_NUMBER, "Post again every this many minutes while the incident is live. Leave it empty to post once.")
          ],
          defaults: { POST_UPDATE::KEY_INCIDENT => "{{trigger.incident.identifier}}", POST_UPDATE::KEY_MESSAGE => "" })

  PAGE = DefinedWorkflow::Steps::PageOnCall
  runtime(PAGE, icon: ICON_PAGE, editor: EDITOR_FIELDS,
          description: "Pages whoever is on call through the on-call tool, reading who that is first, or escalates to a member without one.",
          fields: lambda { |facts|
            tools = facts.workspace ? Integrations::Paging.connections(facts.workspace).map(&:slug) : []
            paging = [ field(PAGE::KEY_TARGET, ToolField::KIND_TEXT, "What to page in the on-call tool, such as a service there.", required: true),
                       field(PAGE::KEY_TOOL, ToolField::KIND_SELECT, "The on-call tool, when there are several.", options: tools, required: tools.size > 1),
                       field(PAGE::KEY_PERSON, ToolField::KIND_TEXT, "Who to page, by email, when you know.") ]
            escalate = [ field(PAGE::KEY_ESCALATE_TO, ToolField::KIND_TEXT, "Who to escalate to, by email, since no on-call tool is connected.", required: true) ]
            [ field(PAGE::KEY_INCIDENT, ToolField::KIND_TEXT, "The incident it pages for.", required: true),
              field(PAGE::KEY_REASON, ToolField::KIND_PARAGRAPH, "What the person paged needs to know.", required: true), *(tools.any? ? paging : escalate) ]
          },
          defaults: { PAGE::KEY_INCIDENT => "{{trigger.incident.identifier}}", PAGE::KEY_REASON => "" })

  FOLLOW_UP = DefinedWorkflow::Steps::CreateFollowUp
  runtime(FOLLOW_UP, icon: ICON_FOLLOW_UP, editor: EDITOR_FIELDS,
          description: "Adds a follow up to an incident, assigned or not, and opens its issue in the workspace's tracker when you ask.",
          fields: [
            field(FOLLOW_UP::KEY_INCIDENT, ToolField::KIND_TEXT, "The incident it follows up.", required: true),
            field(FOLLOW_UP::KEY_DESCRIPTION, ToolField::KIND_TEXT, "What needs doing, in one line.", required: true),
            field(FOLLOW_UP::KEY_MEMBER, ToolField::KIND_TEXT, "Who it is assigned to, by email."),
            field(FOLLOW_UP::KEY_KIND, ToolField::KIND_SELECT, "After the incident (followup) or during it (action).", options: IncidentAction::ACTION_TYPES),
            field(FOLLOW_UP::KEY_OPEN_ISSUE, ToolField::KIND_TOGGLE, "Open its issue in the workspace's tracker too."),
            field(DefinedWorkflow::Steps::Base::KEY_UNDO, ToolField::KIND_TEXT, "How a person puts it back, such as deleting the follow up.", required: true)
          ],
          defaults: { FOLLOW_UP::KEY_INCIDENT => "{{trigger.incident.identifier}}", FOLLOW_UP::KEY_DESCRIPTION => "",
                      FOLLOW_UP::KEY_KIND => IncidentAction::ACTION_TYPE_FOLLOWUP, DefinedWorkflow::Steps::Base::KEY_UNDO => "Delete the follow up." })

  MESSAGE = DefinedWorkflow::Steps::MessagePerson
  runtime(MESSAGE, icon: ICON_PERSON, editor: EDITOR_FIELDS,
          description: "Sends a direct message as Firefight to a member, an incident's lead, a role's holder or whoever is on call for it.",
          fields: lambda { |facts|
            [ field(MESSAGE::KEY_TO, ToolField::KIND_SELECT, "Who it messages.", options: MESSAGE::TO, required: true),
              field(MESSAGE::KEY_PERSON, ToolField::KIND_TEXT, "The person, by email.", required: true, shown_when: { MESSAGE::KEY_TO => [ MESSAGE::TO_PERSON ] }),
              field(MESSAGE::KEY_INCIDENT, ToolField::KIND_TEXT, "The incident whose people it messages.", required: true,
                    shown_when: { MESSAGE::KEY_TO => MESSAGE::FROM_INCIDENT }),
              field(MESSAGE::KEY_ROLE, ToolField::KIND_SELECT, "The role whose holder it messages.", options: slugs(facts) { |workspace| workspace.incident_roles.active.ordered },
                    required: true, shown_when: { MESSAGE::KEY_TO => [ MESSAGE::TO_ROLE ] }),
              field(MESSAGE::KEY_MESSAGE, ToolField::KIND_PARAGRAPH, "What it says, in Markdown.", required: true) ]
          },
          defaults: { MESSAGE::KEY_TO => MESSAGE::TO_LEAD, MESSAGE::KEY_INCIDENT => "{{trigger.incident.identifier}}", MESSAGE::KEY_MESSAGE => "" })

  runtime(DefinedWorkflow::Steps::StatusPageUpdate, icon: ICON_STATUS_PAGE, editor: EDITOR_STATUS_PAGE,
          description: "Posts or updates a status page through a connected status page tool, such as a status report.",
          defaults: { CONFIG_TOOL => "", CONFIG_ARGUMENTS => {} })

  # A change a sandbox step says it makes, which then needs its undo.
  SANDBOX_CHANGES = { DefinedWorkflow::Steps::Sandbox::KEY_CHANGES => [ "true" ] }.freeze

  def sandbox_fields
    [ field(DefinedWorkflow::Steps::Sandbox::KEY_DATA, ToolField::KIND_PARAGRAPH, "What it is given, placed as the file $STEP_DATA, usually an earlier value."),
      field(DefinedWorkflow::Steps::Sandbox::KEY_CHANGES, ToolField::KIND_TOGGLE, "It changes something, so its ff calls may change things and it needs its undo."),
      field(DefinedWorkflow::Steps::Base::KEY_UNDO, ToolField::KIND_TEXT, "How a person puts it back.", required: true, shown_when: SANDBOX_CHANGES),
      field(DefinedWorkflow::Steps::Sandbox::KEY_TIMEOUT, ToolField::KIND_NUMBER, "How long it may run, in seconds, 1 to 900. 120 when left empty.") ]
  end

  runtime(DefinedWorkflow::Steps::RunCommand, icon: ICON_TERMINAL, editor: EDITOR_FIELDS,
          description: "Runs one shell command in the run's sandbox, with ff for the connected tools. It only reads unless you say it changes something.",
          fields: [ field(DefinedWorkflow::Steps::RunCommand::KEY_COMMAND, ToolField::KIND_PARAGRAPH, "The command, such as ff search_logs query=error.", required: true),
                    *sandbox_fields ],
          defaults: { DefinedWorkflow::Steps::RunCommand::KEY_COMMAND => "" })

  SCRIPT = DefinedWorkflow::Steps::RunScript
  runtime(SCRIPT, icon: ICON_SCRIPT, editor: EDITOR_FIELDS,
          description: "Runs a Python, Ruby or JavaScript script in the run's sandbox, with step data in and JSON out.",
          fields: [ field(SCRIPT::KEY_LANGUAGE, ToolField::KIND_SELECT, "The language it is written in.", options: SCRIPT::LANGUAGES, required: true),
                    field(SCRIPT::KEY_SCRIPT, ToolField::KIND_PARAGRAPH, "The script. It reads its data as JSON on its input and prints JSON last.", required: true),
                    *sandbox_fields ],
          defaults: { SCRIPT::KEY_LANGUAGE => SCRIPT::LANGUAGE_PYTHON,
                      SCRIPT::KEY_SCRIPT => "import json, sys\n\ndata = json.load(sys.stdin)\nprint(json.dumps({\"seen\": data}))\n" })

  OUTSIDE = DefinedWorkflow::Steps::CheckFromOutside
  runtime(OUTSIDE, icon: ICON_GLOBE, editor: EDITOR_FIELDS,
          description: "Checks an address from outside as a user meets it: whether it answers, its status, TLS certificate and DNS.",
          fields: [ field(OUTSIDE::KEY_URL, ToolField::KIND_TEXT, "The address, such as https://shop.example.com.", required: true),
                    field(OUTSIDE::KEY_METHOD, ToolField::KIND_SELECT, "How it asks, GET when left empty.", options: OUTSIDE::METHODS) ],
          defaults: { OUTSIDE::KEY_URL => "" })

  runtime(DefinedWorkflow::Steps::Browser, icon: ICON_BROWSER, editor: EDITOR_BROWSER,
          description: "Opens a page in Halon's browser on desktop and phone, follows a path and reports what it saw, with screenshots.",
          defaults: { DefinedWorkflow::Steps::Browser::KEY_URL => "", DefinedWorkflow::Steps::Browser::KEY_STEPS => [] })

  HTTP = DefinedWorkflow::Steps::HttpRequest
  runtime(HTTP, icon: ICON_GLOBE, editor: EDITOR_FIELDS,
          description: "Sends one HTTP request, kept off private networks. GET and HEAD read, any other method changes something.",
          fields: lambda { |facts|
            connections = facts.workspace ? facts.workspace.integrations.where(deleted_at: nil).order(:name).pluck(:slug) : []
            changing = { HTTP::KEY_METHOD => HTTP::METHODS - HTTP::READS }
            [ field(HTTP::KEY_METHOD, ToolField::KIND_SELECT, "How it asks.", options: HTTP::METHODS, required: true),
              field(HTTP::KEY_URL, ToolField::KIND_TEXT, "The address, such as https://api.example.com/deploys.", required: true),
              field(HTTP::KEY_HEADERS, ToolField::KIND_LIST, "Headers, each Name: value, never a secret. Name a connection for credentials."),
              field(HTTP::KEY_CONNECTION, ToolField::KIND_SELECT, "A connection whose credentials go with it, to that connection's own hosts only.",
                    options: connections),
              field(HTTP::KEY_BODY, ToolField::KIND_PARAGRAPH, "What it sends, usually an earlier value.", shown_when: changing),
              field(DefinedWorkflow::Steps::Base::KEY_UNDO, ToolField::KIND_TEXT, "How a person puts it back.", required: true, shown_when: changing) ]
          },
          defaults: { HTTP::KEY_METHOD => "GET", HTTP::KEY_URL => "" })

  WEBHOOK = DefinedWorkflow::Steps::SendWebhook
  runtime(WEBHOOK, icon: ICON_WEBHOOK, editor: EDITOR_FIELDS,
          description: "Sends a signed POST with the run's data through one of the workspace's outbound webhooks.",
          fields: lambda { |facts|
            names = facts.workspace ? facts.workspace.webhooks.active.ordered.pluck(:name) : []
            [ field(WEBHOOK::KEY_WEBHOOK, ToolField::KIND_SELECT, "The outbound webhook it sends through.", options: names, required: true),
              field(WEBHOOK::KEY_EVENT, ToolField::KIND_TEXT, "Its event type, such as workflow.release. The workflow's own by default."),
              field(WEBHOOK::KEY_PAYLOAD, ToolField::KIND_PARAGRAPH, "What it sends, usually an earlier value.") ]
          },
          defaults: { WEBHOOK::KEY_WEBHOOK => "", WEBHOOK::KEY_PAYLOAD => "" })

  SET_DATA = DefinedWorkflow::Steps::SetData
  runtime(SET_DATA, icon: ICON_DATA, editor: EDITOR_SET_DATA,
          description: "Names values for later steps, or picks what they need out of bigger data.",
          defaults: { SET_DATA::KEY_VALUES => [ { SET_DATA::VALUE_NAME => "", SET_DATA::VALUE_VALUE => "" } ] })

  WAIT = DefinedWorkflow::Steps::Waiting
  ASK = DefinedWorkflow::Steps::AskPerson
  runtime(ASK, icon: ICON_PERSON, editor: EDITOR_ASK_PERSON,
          description: "Asks a person a question with choices or a short form, in a direct message and on the run, and waits for the answer.",
          fields: lambda { |facts|
            [ field(ASK::KEY_QUESTION, ToolField::KIND_PARAGRAPH, "What they are asked.", required: true),
              field(ASK::KEY_DETAILS, ToolField::KIND_PARAGRAPH, "What they should know to answer, usually an earlier value."),
              field(ASK::PEOPLE::KEY_TO, ToolField::KIND_SELECT, "Who it asks.", options: ASK::PEOPLE::TO, required: true),
              field(ASK::PEOPLE::KEY_PERSON, ToolField::KIND_TEXT, "The person, by email.", required: true, shown_when: { ASK::PEOPLE::KEY_TO => [ ASK::PEOPLE::TO_PERSON ] }),
              field(ASK::PEOPLE::KEY_INCIDENT, ToolField::KIND_TEXT, "The incident whose people it asks.", required: true,
                    shown_when: { ASK::PEOPLE::KEY_TO => ASK::PEOPLE::FROM_INCIDENT }),
              field(ASK::PEOPLE::KEY_ROLE, ToolField::KIND_SELECT, "The role whose holder it asks.", options: slugs(facts) { |workspace| workspace.incident_roles.active.ordered },
                    required: true, shown_when: { ASK::PEOPLE::KEY_TO => [ ASK::PEOPLE::TO_ROLE ] }) ]
          },
          defaults: { ASK::KEY_QUESTION => "", ASK::PEOPLE::KEY_TO => ASK::PEOPLE::TO_PERSON, ASK::KEY_CHOICES => [], ASK::KEY_FIELDS => [],
                      WAIT::KEY_WAIT => WAIT::DEFAULT_MINUTES },
          routes: ->(step) { ASK.routes_of(step["config"].to_h) }, route_labels: ->(step) { ASK.route_labels(step["config"].to_h) })

  APPROVAL = DefinedWorkflow::Steps::Approval
  runtime(APPROVAL, icon: ICON_APPROVAL, editor: EDITOR_APPROVAL,
          description: "Asks named people or a role to approve before the run goes on, in a channel, on the Approvals page and on the run.",
          fields: [
            field(APPROVAL::KEY_QUESTION, ToolField::KIND_PARAGRAPH, "What approvers decide, such as Release checkout to production?", required: true),
            field(APPROVAL::KEY_DETAILS, ToolField::KIND_PARAGRAPH, "What they should know to decide, usually an earlier value."),
            field(APPROVAL::KEY_WHO, ToolField::KIND_SELECT, "Who approves.", options: APPROVAL::WHO, required: true),
            field(APPROVAL::KEY_APPROVERS, ToolField::KIND_LIST, "The people who approve, by email. Any one of them decides.", required: true,
                  shown_when: { APPROVAL::KEY_WHO => [ APPROVAL::WHO_PEOPLE ] }),
            field(APPROVAL::KEY_ROLE, ToolField::KIND_SELECT, "The workspace role that approves. Anyone holding it decides.", options: APPROVAL::ROLES,
                  required: true, shown_when: { APPROVAL::KEY_WHO => [ APPROVAL::WHO_ROLE ] }),
            field(APPROVAL::KEY_INCIDENT, ToolField::KIND_TEXT, "The incident it is about, such as {{trigger.incident.identifier}}, so its conditions are read again.")
          ],
          defaults: { APPROVAL::KEY_QUESTION => "", APPROVAL::KEY_WHO => APPROVAL::WHO_ROLE, APPROVAL::KEY_ROLE => WorkspaceMembership.roles[:admin],
                      APPROVAL::KEY_CONDITIONS => [], WAIT::KEY_WAIT => WAIT::DEFAULT_MINUTES },
          routes: ->(_step) { APPROVAL::ROUTES },
          conditions: ->(facts) { Workflow::TriggerKinds.incident_conditions(facts) })

  MANUAL = DefinedWorkflow::Steps::Manual
  runtime(MANUAL, icon: ICON_TASK, editor: EDITOR_MANUAL,
          description: "Pauses the run and gives a person a task, with Done in chat and on the run, and goes on once it is done.",
          fields: [
            field(MANUAL::KEY_TASK, ToolField::KIND_PARAGRAPH, "What needs doing, such as Open a ticket with the payment provider.", required: true),
            field(MANUAL::KEY_TO, ToolField::KIND_SELECT, "Who does it. Anyone is asked in a channel, the others by direct message.", options: MANUAL::TO, required: true),
            field(MANUAL::KEY_PERSON, ToolField::KIND_TEXT, "The person, by email.", required: true, shown_when: { MANUAL::KEY_TO => [ MANUAL::TO_PERSON ] }),
            field(MANUAL::KEY_INCIDENT, ToolField::KIND_TEXT, "The incident, such as {{trigger.incident.identifier}}. Its lead does it, or a task for anyone " \
                                                              "is posted in its channel, the owning team's when left empty.",
                  shown_when: { MANUAL::KEY_TO => MANUAL::IN_INCIDENT }),
            field(MANUAL::KEY_NOTE, ToolField::KIND_TEXT, "A short note to write when it is done, such as Ticket number. Later steps read it as note.")
          ],
          defaults: { MANUAL::KEY_TASK => "", MANUAL::KEY_TO => MANUAL::TO_PERSON, WAIT::KEY_WAIT => WAIT::DEFAULT_MINUTES },
          routes: ->(_step) { MANUAL::ROUTES })
end
