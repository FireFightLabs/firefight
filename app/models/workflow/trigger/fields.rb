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

  # A deploy or CI run's, a resource's on the map, a security event's and an issue's, some shared.
  KIND = "kind".freeze
  PROVIDER = "provider".freeze
  PLACE = "place".freeze
  REF = "ref".freeze
  NAME = "name".freeze
  DETAIL = "detail".freeze
  PUBLIC = "public".freeze
  ASKED_BY = "asked_by_email".freeze
  # What a deploy or CI run that ended is, and how it ended (Integrations::RunsEnded speaks these).
  RUN_DEPLOY = "deploy".freeze
  RUN_CI = "ci".freeze
  RUN_KINDS = [ RUN_DEPLOY, RUN_CI ].freeze
  RUN_SUCCEEDED = "succeeded".freeze
  RUN_FAILED = "failed".freeze
  RUN_CANCELLED = "cancelled".freeze
  RUN_OUTCOMES = [ RUN_SUCCEEDED, RUN_FAILED, RUN_CANCELLED ].freeze
  # An inbound webhook's body, each field by this and its path, such as body.service.
  BODY_PREFIX = "body.".freeze

  # Another workflow's run's.
  WORKFLOW = "workflow".freeze
  TRIGGER_KIND = "trigger_kind".freeze
  FAILED_STEP = "failed_step".freeze
end
