# The names of the fields a trigger's conditions read, shared by what offers them (Workflow::TriggerKinds) and what fills
# them in when something happens (Workflow::TriggerPayloads), so the two never disagree on a name.
module Workflow::Trigger::Fields
  # An incident's, for its own triggers and a follow up's.
  SEVERITY = "severity".freeze
  TYPE = "type".freeze
  STATUS = "status".freeze
  STAGE = "stage".freeze
  SOURCE = "source".freeze
  PRIVATE = "private".freeze
  TEST = "test".freeze
  LEAD = "lead".freeze
  # Each custom field, by this and its slug.
  CUSTOM_FIELD_PREFIX = "fields.".freeze
  # What happened, for a kind that says.
  CHANGE = "change".freeze

  # An alert's, beside the normalized fields its provider filled in (service, team, environment, severity_raw, title).
  SERVICE = "service".freeze
  TEAM = "team".freeze
  ENVIRONMENT = "environment".freeze
  SEVERITY_RAW = "severity_raw".freeze
  TITLE = "title".freeze
  OUTCOME = "outcome".freeze
  # What routing did with an alert no rule matched.
  UNMATCHED = "unmatched".freeze

  # A notice's.
  SIGNAL = "signal".freeze
  TOPIC = "topic".freeze
  RESOURCE = "resource".freeze

  # An investigation's.
  SUGGESTS_INCIDENT = "suggests_incident".freeze
  TRIGGER_SOURCE = "trigger_source".freeze
  INCIDENT = "incident".freeze

  # Another workflow's run's.
  WORKFLOW = "workflow".freeze
  TRIGGER_KIND = "trigger_kind".freeze
  FAILED_STEP = "failed_step".freeze
end
