# What the canvas knows about each kind of trigger: its name and one line, its icon, how its settings are drawn and what
# a new one starts with, beside the inputs every trigger asks when it is run by hand. Only a kind something starts runs
# from is registered (Workflow::Trigger::PUBLISHABLE), so the canvas never offers a trigger that would never fire. Run
# by hand, a schedule and once at a time are started by Workflow::Scheduling, and another workflow running this one
# starts it from a Run workflow step, which needs no trigger of its own.
module Workflow::TriggerKinds
  ICON_HAND = "hand".freeze
  ICON_SCHEDULE = "schedule".freeze
  ICON_CLOCK = "clock".freeze
  ICON_INCIDENT = "incident".freeze
  ICON_ALERT = "alert".freeze
  ICON_WEBHOOK = "webhook".freeze
  ICON_DEPLOY = "deploy".freeze
  ICON_HALON = "halon".freeze
  ICON_WORKFLOW = "workflow".freeze
  ICONS = [ ICON_HAND, ICON_SCHEDULE, ICON_CLOCK, ICON_INCIDENT, ICON_ALERT, ICON_WEBHOOK, ICON_DEPLOY, ICON_HALON, ICON_WORKFLOW ].freeze

  # How the settings draw a kind beyond its inputs: nothing more, a repeating schedule, or one date and time. A timed
  # kind's time zone is the person's own when they first choose it.
  EDITOR_NONE = "none".freeze
  EDITOR_SCHEDULE = "schedule".freeze
  EDITOR_ONCE_AT = "once_at".freeze
  EDITORS = [ EDITOR_NONE, EDITOR_SCHEDULE, EDITOR_ONCE_AT ].freeze

  Kind = Data.define(:key, :label, :description, :icon, :editor, :fields, :defaults) do
    def initialize(editor: EDITOR_NONE, fields: [], defaults: {}, **) = super
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
end
