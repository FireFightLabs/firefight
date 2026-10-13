# What starts a run of a workflow. Each has one trigger kind with its own settings and the inputs a person is asked
# when they run it by hand, which every workflow can be. Inputs follow a runbook's rules: a key, a question, a default.
module Workflow::Trigger
  KIND_MANUAL = "manual".freeze
  KIND_SCHEDULE = "schedule".freeze
  KIND_ONCE_AT = "once_at".freeze
  KIND_INCIDENT_DECLARED = "incident_declared".freeze
  KIND_INCIDENT_CHANGED = "incident_changed".freeze
  KIND_ALERT_RECEIVED = "alert_received".freeze
  KIND_INBOUND_WEBHOOK = "inbound_webhook".freeze
  KIND_DEPLOY_FINISHED = "deploy_finished".freeze
  KIND_RESOURCE_CHANGED = "resource_changed".freeze
  KIND_SECURITY_EVENT = "security_event".freeze
  KIND_NOTICE_RAISED = "notice_raised".freeze
  KIND_INVESTIGATION_FINISHED = "investigation_finished".freeze
  KIND_FOLLOW_UP_CHANGED = "follow_up_changed".freeze
  KIND_ISSUE_ASSIGNED = "issue_assigned".freeze
  KIND_RUN_FAILED = "run_failed".freeze
  KIND_CALLED = "called".freeze
  KINDS = [
    KIND_MANUAL, KIND_SCHEDULE, KIND_ONCE_AT, KIND_INCIDENT_DECLARED, KIND_INCIDENT_CHANGED, KIND_ALERT_RECEIVED,
    KIND_INBOUND_WEBHOOK, KIND_DEPLOY_FINISHED, KIND_RESOURCE_CHANGED, KIND_SECURITY_EVENT, KIND_NOTICE_RAISED,
    KIND_INVESTIGATION_FINISHED, KIND_FOLLOW_UP_CHANGED, KIND_ISSUE_ASSIGNED, KIND_RUN_FAILED, KIND_CALLED
  ].freeze

  # What each kind starts on, as a person reads it. A timed trigger says its own time (Workflow::Trigger::Schedule).
  WORDS = {
    KIND_MANUAL => "By hand", KIND_INCIDENT_DECLARED => "When an incident is declared", KIND_INCIDENT_CHANGED => "When an incident changes",
    KIND_ALERT_RECEIVED => "When an alert arrives", KIND_INBOUND_WEBHOOK => "When its webhook is called", KIND_DEPLOY_FINISHED => "When a deploy or CI run ends",
    KIND_RESOURCE_CHANGED => "When a resource changes", KIND_SECURITY_EVENT => "On a security event", KIND_NOTICE_RAISED => "When Halon raises a notice",
    KIND_INVESTIGATION_FINISHED => "When an investigation finishes", KIND_FOLLOW_UP_CHANGED => "When a follow up or postmortem changes",
    KIND_ISSUE_ASSIGNED => "When an issue is assigned to Firefight", KIND_RUN_FAILED => "When another workflow's run fails",
    KIND_CALLED => "When another workflow runs it"
  }.freeze
  # Kinds something happening starts, which share the workspace's ceiling of event runs an hour (Workflow::Limits) and
  # have nobody pressing Run when they start.
  EVENTS = [
    KIND_INCIDENT_DECLARED, KIND_INCIDENT_CHANGED, KIND_ALERT_RECEIVED, KIND_NOTICE_RAISED, KIND_INVESTIGATION_FINISHED,
    KIND_FOLLOW_UP_CHANGED, KIND_RUN_FAILED
  ].freeze
  # The kinds a published workflow may start on, another workflow running it among them. Every other kind is refused
  # when publishing, since nothing would start it.
  PUBLISHABLE = [ KIND_MANUAL, KIND_SCHEDULE, KIND_ONCE_AT, KIND_CALLED, *EVENTS ].freeze

  KEY_KIND = "kind".freeze
  KEY_INPUTS = "inputs".freeze
  # What must hold of the event for it to start a run, as the rule engine's conditions (Policy::Conditions).
  KEY_CONDITIONS = "conditions".freeze
  CONDITION_LIMIT = 20
  INPUT_FIELDS = Runbook::Procedure::INPUT_FIELDS
  INPUT_KEY = Runbook::Procedure::INPUT_KEY
  INPUT_LIMIT = Runbook::Procedure::INPUT_LIMIT

  module_function

  def default = { KEY_KIND => KIND_MANUAL, KEY_INPUTS => [] }

  def inputs(trigger) = Array(trigger.to_h[KEY_INPUTS]).select { |input| input.is_a?(Hash) }

  def input_keys(trigger) = inputs(trigger).map { |input| input["key"] }

  # Each problem with a trigger as a sentence.
  def problems(trigger)
    return [ "The trigger needs its settings." ] unless trigger.is_a?(Hash)

    found = []
    found << "The trigger is a #{trigger[KEY_KIND].presence || 'blank'} trigger, which is not a kind of trigger." unless KINDS.include?(trigger[KEY_KIND])
    given = Array(trigger[KEY_INPUTS])
    found << "The trigger can ask at most #{INPUT_LIMIT} inputs." if given.size > INPUT_LIMIT
    given.each do |input|
      next found << "Each input needs its key and question." unless input.is_a?(Hash)
      next found << "Inputs need keys of lowercase letters, numbers and underscores, such as region." unless input["key"].to_s.match?(INPUT_KEY)

      found << "The trigger needs a question for #{input['key']}." if input["question"].blank?
    end
    keys = input_keys(trigger)
    found << "Each input needs a key of its own." unless keys.uniq.size == keys.size
    found << "A workflow cannot start #{WORDS[trigger[KEY_KIND]].downcase_first} yet." if KINDS.include?(trigger[KEY_KIND]) && !PUBLISHABLE.include?(trigger[KEY_KIND])
    found.concat(Workflow::Trigger::Schedule.problems(trigger))
    found.concat(condition_problems(trigger))
    found.concat(Workflow::TriggerKinds.find(trigger[KEY_KIND])&.problems&.call(trigger).to_a)
    found
  end

  def conditions(trigger) = Array(trigger.to_h[KEY_CONDITIONS]).select { |condition| condition.is_a?(Hash) }

  def event?(kind) = EVENTS.include?(kind.to_s)

  def condition_problems(trigger)
    given = trigger[KEY_CONDITIONS]
    return [] if given.nil?
    return [ "The trigger's conditions must be a list." ] unless given.is_a?(Array)
    return [ "The trigger can hold at most #{CONDITION_LIMIT} conditions." ] if given.size > CONDITION_LIMIT
    return [ "Only a trigger that something happening starts can have conditions." ] if given.any? && !event?(trigger[KEY_KIND])

    Policy::Conditions.errors_for(given).map { |message| "The trigger's #{message.downcase_first}." }
  end

  # When it fires as a person reads it. Every workflow can also be run by hand.
  def words(trigger)
    Workflow::Trigger::Schedule.timed?(trigger) ? Workflow::Trigger::Schedule.words(trigger) : WORDS.fetch(trigger.to_h[KEY_KIND], WORDS[KIND_MANUAL])
  end

  # What a person gave, each input left out taken from its default. missing names those with neither.
  Resolved = Data.define(:values, :missing)

  def resolve_inputs(trigger, given)
    given = given.to_h.stringify_keys.transform_values { |value| value.is_a?(String) ? value.strip : value }
    asked = inputs(trigger)
    values = asked.to_h { |input| [ input["key"], given[input["key"]].presence || input["default"].presence ] }
    Resolved.new(values: values.compact, missing: asked.reject { |input| values[input["key"]].present? })
  end
end
