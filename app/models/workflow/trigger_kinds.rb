# What the canvas knows about each kind of trigger: its name and one line, its icon, how its settings are drawn and what
# a new one starts with, beside the inputs every trigger asks when it is run by hand. Only a kind something starts runs
# from is registered (Workflow::Trigger::PUBLISHABLE), so the canvas never offers a trigger that would never fire. Run
# by hand, a schedule and once at a time are started by Workflow::Scheduling, another workflow running this one starts
# it from a Run workflow step, and every other kind is something happening, heard by Workflow::Trigger::Events.
#
# A kind something happening starts also says what its conditions may read (each a field of the rule engine's context
# with the values the workspace has for it) and what its run's trigger data holds, which later steps read as
# {{trigger.<path>}} and the reference picker offers.
module Workflow::TriggerKinds
  F = Workflow::Trigger::Fields

  ICON_HAND = "hand".freeze
  ICON_SCHEDULE = "schedule".freeze
  ICON_CLOCK = "clock".freeze
  ICON_INCIDENT = "incident".freeze
  ICON_ALERT = "alert".freeze
  ICON_WEBHOOK = "webhook".freeze
  ICON_DEPLOY = "deploy".freeze
  ICON_HALON = "halon".freeze
  ICON_WORKFLOW = "workflow".freeze
  ICON_FOLLOW_UP = "follow_up".freeze
  ICON_FAILED = "failed".freeze
  ICON_MAP = "map".freeze
  ICON_SECURITY = "security".freeze
  ICON_ISSUE = "issue".freeze
  ICONS = [
    ICON_HAND, ICON_SCHEDULE, ICON_CLOCK, ICON_INCIDENT, ICON_ALERT, ICON_WEBHOOK, ICON_DEPLOY, ICON_HALON, ICON_WORKFLOW,
    ICON_FOLLOW_UP, ICON_FAILED, ICON_MAP, ICON_SECURITY, ICON_ISSUE
  ].freeze


  # How the settings draw a kind beyond its inputs: nothing more, a repeating schedule, or one date and time. A timed
  # kind's time zone is the person's own when they first choose it.
  EDITOR_NONE = "none".freeze
  EDITOR_SCHEDULE = "schedule".freeze
  EDITOR_ONCE_AT = "once_at".freeze
  EDITORS = [ EDITOR_NONE, EDITOR_SCHEDULE, EDITOR_ONCE_AT ].freeze

  # A field a condition may read, with the values the workspace has for it when there is a fixed set. A number field is
  # also compared as a number (PolicyRule::NUMBER_OPERATORS).
  ConditionField = Data.define(:key, :label, :options, :number) do
    def initialize(options: [], number: false, **) = super
  end

  # One value a condition may compare against, as stored and as a person reads it.
  Choice = Data.define(:value, :label)

  # One thing a run's trigger data holds, by its path under trigger, and what it is.
  Output = Data.define(:path, :label)

  # fields is a list, or a lambda given the Facts for choices that are the workspace's own. conditions is given the Facts
  # too. problems is given the trigger and answers sentences. help is what an agent writing a workflow reads.
  Kind = Data.define(:key, :label, :description, :icon, :editor, :fields, :defaults, :conditions, :outputs, :help, :problems) do
    def initialize(editor: EDITOR_NONE, fields: [], defaults: {}, conditions: ->(_facts) { [] }, outputs: [], help: nil,
                   problems: ->(_trigger) { [] }, **)
      super
    end

    def fields_for(facts) = fields.respond_to?(:call) ? fields.call(facts) : fields

    def conditions_for(facts) = conditions.call(facts)

    def event? = Workflow::Trigger.event?(key)
  end

  module_function

  def registry = @registry ||= {}

  def register(kind)
    raise ArgumentError, "#{kind.key} is not a kind of trigger" unless Workflow::Trigger::KINDS.include?(kind.key)
    raise ArgumentError, "#{kind.icon} is not an icon a trigger has" unless ICONS.include?(kind.icon)
    raise ArgumentError, "#{kind.editor} is not a way to draw a trigger's settings" unless EDITORS.include?(kind.editor)

    registry[kind.key] = kind
  end

  def all = registry.values

  def find(key) = registry[key.to_s]

  def field(key, kind, description, options: [], required: false)
    ToolField::Field.new(key: key, kind: kind, options: options, required: required, description: description)
  end

  # What an agent writing a workflow reads about every kind it may start on.
  def help = all.filter_map { |kind| "#{kind.key}: #{kind.help}" if kind.help }.join(" ")

  # A choice's values that are not among those offered, as a sentence, or nil.
  def unknown_choices(trigger, key, offered, named)
    given = Array(trigger.to_h[key]).map(&:to_s)
    return "#{named} needs at least one of #{offered.join(', ')}." if given.empty?

    unknown = given - offered
    "#{named} cannot be #{unknown.to_sentence}, only #{offered.join(', ')}." if unknown.any?
  end

  register(Kind.new(
    key: Workflow::Trigger::KIND_MANUAL, label: "Run by hand", icon: ICON_HAND,
    description: "A person runs it from the dashboard, Slack or Halon, answering its inputs."
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_SCHEDULE, label: "On a schedule", icon: ICON_SCHEDULE, editor: EDITOR_SCHEDULE,
    description: "Runs on a repeat, such as every weekday at 09:00 or every two hours, in its own time zone.",
    defaults: { Workflow::Trigger::Schedule::KEY_REPEAT => Workflow::Trigger::Schedule::REPEAT_DAYS, Workflow::Trigger::Schedule::KEY_AT => "09:00",
                Workflow::Trigger::Schedule::KEY_DAYS => Workflow::Trigger::Schedule::WEEKDAYS }
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_ONCE_AT, label: "Once at a time", icon: ICON_CLOCK, editor: EDITOR_ONCE_AT,
    description: "Runs once, at a date and time in its own time zone, and is done after."
  ))

  def choices(pairs) = pairs.map { |value, label| Choice.new(value: value.to_s, label: label.to_s) }

  def flags = choices([ %w[true Yes], %w[false No] ])

  # What a condition on an incident may read: its severity, type, status and stage by their slugs, where it came from,
  # whether it is private or a test, its lead's email and each custom field by what it shows.
  def incident_conditions(facts)
    workspace = facts.workspace
    return [] unless workspace

    stages = IncidentLifecycleStage::KEYS.map { |key| [ key, key.humanize ] }
    sources = [ Incident::SOURCE_SLACK, Incident::SOURCE_ALERT, Incident::SOURCE_DASHBOARD, Incident::SOURCE_MCP ].map { |source| [ source, source.humanize ] }
    custom = workspace.incident_field_definitions.active.ordered.map do |definition|
      ConditionField.new(key: "#{F::CUSTOM_FIELD_PREFIX}#{definition.slug}", label: definition.name,
                         options: choices(definition.selectable_values.values.map { |label| [ label, label ] }))
    end
    [
      ConditionField.new(key: F::SEVERITY, label: "Severity", options: choices(workspace.incident_severities.active.by_rank.pluck(:slug, :name))),
      ConditionField.new(key: F::TYPE, label: "Type", options: choices(workspace.incident_types.active.ordered.pluck(:slug, :name))),
      ConditionField.new(key: F::STATUS, label: "Status", options: choices(workspace.incident_statuses.active.ordered.pluck(:slug, :name))),
      ConditionField.new(key: F::STAGE, label: "Stage", options: choices(stages)),
      ConditionField.new(key: F::SOURCE, label: "Declared from", options: choices(sources)),
      ConditionField.new(key: F::PRIVATE, label: "Private", options: flags),
      ConditionField.new(key: F::TEST, label: "Test incident", options: flags),
      ConditionField.new(key: F::LEAD, label: "Lead's email"),
      *custom
    ]
  end

  INCIDENT_OUTPUTS = [
    Output.new(path: "incident.identifier", label: "The incident's id, such as INC-42"),
    Output.new(path: "incident.name", label: "Its name"),
    Output.new(path: "incident.summary", label: "Its summary"),
    Output.new(path: "incident.severity.name", label: "Its severity"),
    Output.new(path: "incident.status.name", label: "Its status"),
    Output.new(path: "incident.type.name", label: "Its type"),
    Output.new(path: "incident.lead.email", label: "Its lead's email"),
    Output.new(path: "incident.channel_name", label: "Its channel"),
    Output.new(path: "incident.custom_fields", label: "Its custom fields"),
    Output.new(path: "actor.name", label: "Who did it")
  ].freeze

  register(Kind.new(
    key: Workflow::Trigger::KIND_INCIDENT_DECLARED, label: "Incident declared", icon: ICON_INCIDENT,
    description: "Runs when an incident is declared that matches its conditions, such as its severity or type.",
    conditions: method(:incident_conditions), outputs: INCIDENT_OUTPUTS,
    help: "runs when an incident is declared. conditions [{field, operator, value}] read severity, type, status, stage (slugs), source, private, " \
          "test, lead and fields.<custom field slug>, with operator is_one_of (value a list), contains, starts_with, matches_regex or is_empty. " \
          "trigger holds incident (identifier, name, severity, status, type, lead, custom_fields) as outbound webhooks send it."
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_INCIDENT_CHANGED, label: "Incident changed", icon: ICON_INCIDENT,
    description: "Runs once each time an incident changes in a way it chose, such as its severity going up or it being resolved.",
    fields: [
      field(Workflow::Listening::KEY_CHANGES, ToolField::KIND_LIST, "Which changes start it.", options: Workflow::Trigger::Changes::INCIDENT, required: true)
    ],
    defaults: { Workflow::Listening::KEY_CHANGES => [ Workflow::Trigger::Changes::SEVERITY ] },
    conditions: ->(facts) { [ *incident_conditions(facts), ConditionField.new(key: F::CHANGE, label: "What changed") ] },
    outputs: [ *INCIDENT_OUTPUTS, Output.new(path: "change", label: "What changed"), Output.new(path: "changes", label: "Each field's value before and after") ],
    problems: ->(trigger) { [ unknown_choices(trigger, Workflow::Listening::KEY_CHANGES, Workflow::Trigger::Changes::INCIDENT, "What changes it") ].compact },
    help: "runs once each time an incident changes. changes (required) lists which: #{Workflow::Trigger::Changes::INCIDENT.join(', ')}. " \
          "conditions read the incident as incident_declared's do, after the change. trigger holds incident, change and changes (each field's before and after)."
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_ALERT_RECEIVED, label: "Alert received", icon: ICON_ALERT,
    description: "Runs once for each alert routing lets through, after grouping, so a storm of the same alert starts one run.",
    conditions: lambda { |facts|
      sources = facts.workspace ? facts.workspace.alert_sources.order(:name).pluck(:name).map { |name| [ name, name ] } : []
      outcomes = [ *PolicyRule::AlertRoutingOutcome::ACTIONS - [ PolicyRule::AlertRoutingOutcome::ACTION_DROP ], F::UNMATCHED ]
      [
        ConditionField.new(key: F::SERVICE, label: "Service"), ConditionField.new(key: F::TEAM, label: "Team"),
        ConditionField.new(key: F::ENVIRONMENT, label: "Environment"), ConditionField.new(key: F::SEVERITY_RAW, label: "Severity the tool sent"),
        ConditionField.new(key: F::TITLE, label: "Title"), ConditionField.new(key: F::SOURCE, label: "Alert source", options: choices(sources)),
        ConditionField.new(key: F::OUTCOME, label: "What routing did", options: choices(outcomes.map { |outcome| [ outcome, outcome.humanize ] }))
      ]
    },
    outputs: [
      Output.new(path: "alert.title", label: "The alert's title"), Output.new(path: "alert.description", label: "What it says"),
      Output.new(path: "alert.service", label: "Its service"), Output.new(path: "alert.severity_raw", label: "Its severity, as the tool sent it"),
      Output.new(path: "alert.url", label: "Its page in the tool"), Output.new(path: "alert.source", label: "Its alert source"),
      Output.new(path: "outcome", label: "What routing did"), Output.new(path: "incident.identifier", label: "The incident it joined, when it did")
    ],
    help: "runs once per alert routing lets through, after grouping (an alert joining an open group starts nothing, a dropped one neither). " \
          "conditions read service, team, environment, severity_raw, title, source, outcome (auto_create_incident, attach_to_incident, notify_only, unmatched) " \
          "and the catalog's service.<attribute>. trigger holds alert, outcome and incident."
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_NOTICE_RAISED, label: "Halon raised a notice", icon: ICON_HALON,
    description: "Runs when Halon raises a problem, from a check, a security event or a workflow, or when one gets worse.",
    conditions: lambda { |_facts|
      [
        ConditionField.new(key: F::CHANGE, label: "New or worse", options: choices(Investigation::Notice::CHANGES.map { |change| [ change, change.humanize ] })),
        ConditionField.new(key: F::SIGNAL, label: "Kind of problem", options: choices(Investigation::Notice::SIGNAL_LABELS)),
        ConditionField.new(key: F::SEVERITY, label: "How bad", options: choices(Investigation::Notice::SEVERITY_LABELS)),
        ConditionField.new(key: F::TOPIC, label: "What it is about"), ConditionField.new(key: F::RESOURCE, label: "Resource on the map")
      ]
    },
    outputs: [
      Output.new(path: "notice.topic", label: "What it is about"), Output.new(path: "notice.summary", label: "What it says"),
      Output.new(path: "notice.severity", label: "How bad it is"), Output.new(path: "notice.signal", label: "What kind of problem"),
      Output.new(path: "notice.resource", label: "The resource it is about"), Output.new(path: "change", label: "Raised or worsened")
    ],
    help: "runs when Halon raises a notice or one gets worse. conditions read change (raised or worsened), signal, severity, topic and resource. " \
          "A workflow never hears a notice its own run raised. trigger holds notice and change."
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_INVESTIGATION_FINISHED, label: "Investigation finished", icon: ICON_HALON,
    description: "Runs when a Halon investigation concludes or gives up, with what it found and how sure it is.",
    conditions: lambda { |_facts|
      [
        ConditionField.new(key: F::STATUS, label: "How it ended", options: choices([ [ Investigation::STATUS_SUCCEEDED, "Concluded" ], [ Investigation::STATUS_FAILED, "Gave up" ] ])),
        ConditionField.new(key: F::SUGGESTS_INCIDENT, label: "Suggests an incident", options: flags),
        ConditionField.new(key: F::TRIGGER_SOURCE, label: "What started it", options: choices(Investigation::TRIGGER_SOURCES.map { |source| [ source, source.humanize ] })),
        ConditionField.new(key: F::INCIDENT, label: "Incident id")
      ]
    },
    outputs: [
      Output.new(path: "investigation.finding", label: "What it found"), Output.new(path: "investigation.confidence", label: "How sure it is, from 0 to 1"),
      Output.new(path: "investigation.question", label: "What it looked into"), Output.new(path: "investigation.url", label: "Its page"),
      Output.new(path: "investigation.status", label: "How it ended"), Output.new(path: "incident.identifier", label: "Its incident, when it has one")
    ],
    help: "runs when an investigation concludes (status succeeded) or gives up (failed). conditions read status, suggests_incident, trigger_source " \
          "and incident. trigger holds investigation (finding, confidence 0 to 1, question, url) and incident."
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_FOLLOW_UP_CHANGED, label: "Follow up or postmortem changed", icon: ICON_FOLLOW_UP,
    description: "Runs when a follow up is created or completed, or a postmortem is started or completed.",
    fields: [
      field(Workflow::Listening::KEY_CHANGES, ToolField::KIND_LIST, "Which changes start it.", options: Workflow::Trigger::Changes::FOLLOW_UP, required: true)
    ],
    defaults: { Workflow::Listening::KEY_CHANGES => [ Workflow::Trigger::Changes::FOLLOW_UP_CREATED ] },
    conditions: method(:incident_conditions),
    outputs: [ *INCIDENT_OUTPUTS, Output.new(path: "action.description", label: "The follow up"), Output.new(path: "postmortem.title", label: "The postmortem"),
               Output.new(path: "change", label: "What changed") ],
    problems: ->(trigger) { [ unknown_choices(trigger, Workflow::Listening::KEY_CHANGES, Workflow::Trigger::Changes::FOLLOW_UP, "What changes it") ].compact },
    help: "runs when a follow up or postmortem changes. changes (required) lists which: #{Workflow::Trigger::Changes::FOLLOW_UP.join(', ')}. " \
          "conditions read its incident as incident_declared's do. trigger holds incident, action (a follow up) or postmortem, and change."
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_RUN_FAILED, label: "Another workflow's run failed", icon: ICON_FAILED,
    description: "Runs when a run of another workflow fails, to tell someone or put it right.",
    conditions: lambda { |facts|
      named = facts.workspace ? Workflow.where(workspace: facts.workspace).ordered.pluck(:slug, :name) : []
      [ ConditionField.new(key: F::WORKFLOW, label: "Workflow", options: choices(named)), ConditionField.new(key: F::FAILED_STEP, label: "Step that failed"),
        ConditionField.new(key: F::TRIGGER_KIND, label: "What started it", options: choices(Workflow::Trigger::WORDS)) ]
    },
    outputs: [
      Output.new(path: "run.workflow", label: "The workflow"), Output.new(path: "run.error", label: "Why it failed"),
      Output.new(path: "run.failed_step", label: "The step that failed"), Output.new(path: "run.url", label: "The run's page")
    ],
    help: "runs when a real run of another workflow fails (never its own, a test run or one another workflow ran). conditions read workflow (its slug), " \
          "failed_step and trigger_kind. trigger holds run (workflow, error, failed_step, url)."
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_INBOUND_WEBHOOK, label: "Inbound webhook", icon: ICON_WEBHOOK,
    description: "Runs when a signed POST reaches the workflow's own address, with what it was sent.",
    outputs: [
      Output.new(path: "body", label: "Everything it was sent"), Output.new(path: "received_at", label: "When it arrived"),
      Output.new(path: "delivery", label: "The sender's id for the delivery, when it gave one")
    ],
    help: "runs when a JSON object is POSTed to the workflow's own address, signed as Firefight's outbound webhooks are (X-Firefight-Timestamp, " \
          "X-Firefight-Signature v1=HMAC-SHA256 of v1:<timestamp>:<body> with the workflow's secret). conditions read body.<path>, such as body.service. " \
          "trigger holds body, received_at and delivery."
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_DEPLOY_FINISHED, label: "Deploy or CI finished", icon: ICON_DEPLOY,
    description: "Runs when a connected code host or deploy platform says a deploy or a CI run ended, with how it ended.",
    conditions: lambda { |_facts|
      [
        ConditionField.new(key: F::KIND, label: "Deploy or CI", options: choices([ [ F::RUN_DEPLOY, "Deploy" ], [ F::RUN_CI, "CI run" ] ])),
        ConditionField.new(key: F::OUTCOME, label: "How it ended", options: choices(F::RUN_OUTCOMES.map { |outcome| [ outcome, outcome.humanize ] })),
        ConditionField.new(key: F::PLACE, label: "Repository, site or project"), ConditionField.new(key: F::REF, label: "Branch"),
        ConditionField.new(key: F::ENVIRONMENT, label: "Environment"), ConditionField.new(key: F::NAME, label: "Its name"),
        ConditionField.new(key: F::PROVIDER, label: "Where it ran")
      ]
    },
    outputs: [
      Output.new(path: "run.outcome", label: "How it ended"), Output.new(path: "run.kind", label: "Deploy or CI"),
      Output.new(path: "run.name", label: "Its name"), Output.new(path: "run.place", label: "The repository, site or project"),
      Output.new(path: "run.ref", label: "The branch"), Output.new(path: "run.commit", label: "The commit"),
      Output.new(path: "run.environment", label: "The environment"), Output.new(path: "run.url", label: "Its page")
    ],
    help: "runs when a connection reports a deploy or CI run ended. conditions read kind (deploy or ci), outcome (succeeded, failed, cancelled), " \
          "place, ref, environment, name and provider. trigger holds run (kind, outcome, name, place, ref, commit, environment, url)."
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_RESOURCE_CHANGED, label: "Resource changed", icon: ICON_MAP,
    description: "Runs when the map records a change on a resource: it appeared, went away, deployed, changed status, was renamed or a setting moved.",
    conditions: lambda { |_facts|
      [
        ConditionField.new(key: F::CHANGE, label: "What changed", options: choices(ResourceMap::Change::KINDS.map { |kind| [ kind, kind.humanize ] })),
        ConditionField.new(key: F::KIND, label: "Kind of resource", options: choices(ResourceMap::KINDS.map { |kind| [ kind, kind.humanize ] })),
        ConditionField.new(key: F::NAME, label: "Resource name"), ConditionField.new(key: F::PROVIDER, label: "Where it runs"),
        ConditionField.new(key: F::DETAIL, label: "The setting that moved")
      ]
    },
    outputs: [
      Output.new(path: "change.words", label: "What changed, in words"), Output.new(path: "change.kind", label: "What kind of change"),
      Output.new(path: "change.from", label: "What it was"), Output.new(path: "change.to", label: "What it is now"),
      Output.new(path: "resource.name", label: "The resource"), Output.new(path: "resource.kind", label: "Its kind"), Output.new(path: "resource.url", label: "Its page")
    ],
    help: "runs when the map records a change on a resource. conditions read change (#{ResourceMap::Change::KINDS.join(', ')}), kind, name, provider and detail. " \
          "trigger holds change (kind, from, to, detail, words) and resource (name, kind, provider, url)."
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_SERVICE_SCALED, label: "Service scaled", icon: ICON_MAP,
    description: "Runs when the map sees a service run more or fewer instances than before, with how many it ran and runs now.",
    conditions: lambda { |_facts|
      [
        ConditionField.new(key: F::TO, label: "Instances after", number: true), ConditionField.new(key: F::FROM, label: "Instances before", number: true),
        ConditionField.new(key: F::NAME, label: "Resource name"), ConditionField.new(key: F::PROVIDER, label: "Where it runs"),
        ConditionField.new(key: F::KIND, label: "Kind of resource", options: choices(ResourceMap::KINDS.map { |kind| [ kind, kind.humanize ] }))
      ]
    },
    outputs: [
      Output.new(path: "change.from", label: "How many instances it ran"), Output.new(path: "change.to", label: "How many it runs now"),
      Output.new(path: "change.words", label: "What changed, in words"), Output.new(path: "resource.name", label: "The service"),
      Output.new(path: "resource.provider", label: "Where it runs"), Output.new(path: "resource.url", label: "Its page")
    ],
    help: "runs when the map sees a service's instance count change, on every provider whose registry entry says scaling firefight. " \
          "conditions read to and from (the counts after and before, compared with greater_than or less_than and a number, or is_one_of), " \
          "name, provider and kind. trigger holds change (kind scaled, from and to as numbers, words) and resource (name, kind, provider, url)."
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_SECURITY_EVENT, label: "Security event", icon: ICON_SECURITY,
    description: "Runs when a connected provider reports a security event, such as a secret that leaked into a repository.",
    conditions: lambda { |_facts|
      [ ConditionField.new(key: F::KIND, label: "What happened"), ConditionField.new(key: F::PLACE, label: "Repository or account"),
        ConditionField.new(key: F::PUBLIC, label: "Known to be public", options: flags), ConditionField.new(key: F::PROVIDER, label: "Who reported it") ]
    },
    outputs: [
      Output.new(path: "event.what", label: "What it is about"), Output.new(path: "event.place", label: "The repository or account"),
      Output.new(path: "event.url", label: "Its page"), Output.new(path: "event.public", label: "Whether it is public"), Output.new(path: "event.kind", label: "What happened")
    ],
    help: "runs when a provider reports a security event, such as a leaked secret. conditions read kind (leaked_secret), place, public and provider. " \
          "trigger holds event (kind, what, place, url, public, reference)."
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_ISSUE_ASSIGNED, label: "Issue assigned to Firefight", icon: ICON_ISSUE,
    description: "Runs when someone assigns or hands an issue to Firefight in a connected tracker, beside Halon taking it up, or adds the label it names.",
    fields: lambda { |_facts|
      named = Integrations::IssueLabels.providers.map(&:name).to_sentence(two_words_connector: " or ", last_word_connector: " or ")
      [ field(Workflow::Listening::KEY_LABEL, ToolField::KIND_TEXT,
              "Or when an issue gets this label#{" in #{named}" if named.present?}, whatever its case. Leave it empty to run only when an issue is assigned.") ]
    },
    conditions: lambda { |_facts|
      [ ConditionField.new(key: F::TITLE, label: "Issue title"), ConditionField.new(key: F::ASKED_BY, label: "Who assigned it, by email"),
        ConditionField.new(key: F::PROVIDER, label: "Tracker") ]
    },
    outputs: [
      Output.new(path: "issue.key", label: "The issue's key"), Output.new(path: "issue.title", label: "Its title"), Output.new(path: "issue.url", label: "Its page"),
      Output.new(path: "issue.text", label: "What was asked"), Output.new(path: "issue.asked_by", label: "Who assigned or labelled it"),
      Output.new(path: "issue.how", label: "Assigned or labelled"), Output.new(path: "issue.labels", label: "The labels added")
    ],
    help: "runs when an issue is assigned or handed to Firefight in a tracker, and, when label names one, when someone adds that label to an " \
          "issue in a tracker that reports it (case does not matter). conditions read title, asked_by_email and provider. " \
          "trigger holds issue (key, title, url, text, asked_by, asked_by_email, how (assigned or labelled), labels)."
  ))

  register(Kind.new(
    key: Workflow::Trigger::KIND_CALLED, label: "Called by a workflow", icon: ICON_WORKFLOW,
    description: "Another workflow runs it from a Run workflow step, with its inputs, and takes what it hands back.",
    outputs: [ Output.new(path: "workflow", label: "The workflow that ran it"), Output.new(path: "run_id", label: "The run that ran it") ],
    help: "another workflow runs it from a run_workflow step, giving its inputs. trigger holds workflow and run_id."
  ))
end
