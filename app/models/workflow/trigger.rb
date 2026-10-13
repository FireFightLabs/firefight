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

  KEY_KIND = "kind".freeze
  KEY_INPUTS = "inputs".freeze
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
    found
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
