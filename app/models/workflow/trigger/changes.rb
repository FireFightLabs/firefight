# What about an incident, a follow up or a postmortem happened, read from the incident's timeline event, so a trigger can
# choose which changes start it. One event can be more than one change: resolving an incident also changes its status.
module Workflow::Trigger::Changes
  STATUS = "status".freeze
  SEVERITY = "severity".freeze
  TYPE = "type".freeze
  LEAD = "lead".freeze
  ROLE = "role".freeze
  CUSTOM_FIELD = "custom_field".freeze
  ACCEPTED = "accepted".freeze
  RESOLVED = "resolved".freeze
  REOPENED = "reopened".freeze
  CANCELLED = "cancelled".freeze
  ESCALATED = "escalated".freeze
  INCIDENT = [ STATUS, SEVERITY, TYPE, LEAD, ROLE, CUSTOM_FIELD, ACCEPTED, RESOLVED, REOPENED, CANCELLED, ESCALATED ].freeze

  FOLLOW_UP_CREATED = "follow_up_created".freeze
  FOLLOW_UP_COMPLETED = "follow_up_completed".freeze
  POSTMORTEM_STARTED = "postmortem_started".freeze
  # A postmortem is done when its status reaches completed, which is when a team publishes it.
  POSTMORTEM_COMPLETED = "postmortem_completed".freeze
  FOLLOW_UP = [ FOLLOW_UP_CREATED, FOLLOW_UP_COMPLETED, POSTMORTEM_STARTED, POSTMORTEM_COMPLETED ].freeze

  # What an incident update names as changed (Incident::Snapshots), and the change each is.
  COLUMNS = {
    "status" => STATUS, "severity" => SEVERITY, "type" => TYPE, "lead" => LEAD,
    "custom_fields" => CUSTOM_FIELD
  }.freeze

  # The incident's associations those name, which a change is read as by name before and after.
  NAMED_COLUMNS = { "status" => :incident_status, "severity" => :incident_severity, "type" => :incident_type, "lead" => :lead }.freeze

  BY_EVENT = {
    IncidentEvent::INCIDENT_ACCEPTED => [ ACCEPTED, STATUS ], IncidentEvent::INCIDENT_RESOLVED => [ RESOLVED, STATUS ],
    IncidentEvent::INCIDENT_REOPENED => [ REOPENED, STATUS ], IncidentEvent::INCIDENT_CANCELED => [ CANCELLED, STATUS ],
    IncidentEvent::MERGED_INTO => [ CANCELLED, STATUS ], IncidentEvent::LEAD_ASSIGNED => [ LEAD ],
    IncidentEvent::ROLE_ASSIGNED => [ ROLE ], IncidentEvent::ROLE_UNASSIGNED => [ ROLE ], IncidentEvent::INCIDENT_ESCALATED => [ ESCALATED ]
  }.freeze

  FOLLOW_UP_EVENTS = {
    IncidentEvent::ACTION_CREATED => FOLLOW_UP_CREATED, IncidentEvent::ACTION_COMPLETED => FOLLOW_UP_COMPLETED,
    IncidentEvent::POSTMORTEM_STARTED => POSTMORTEM_STARTED, IncidentEvent::POSTMORTEM_GENERATED => POSTMORTEM_STARTED
  }.freeze

  module_function

  # The incident changes an event is, empty for one that changes none of them.
  def incident(event)
    named = COLUMNS.filter_map { |column, change| change if Array(event.changed_fields).include?(column) }
    named = [] if event.event_type == IncidentEvent::INCIDENT_CREATED
    (BY_EVENT.fetch(event.event_type, []) + named).uniq
  end

  # The follow up or postmortem change an event is, nil for none.
  def follow_up(event)
    return FOLLOW_UP_EVENTS[event.event_type] if FOLLOW_UP_EVENTS.key?(event.event_type)
    return unless event.event_type == IncidentEvent::POSTMORTEM_EDITED

    update = event.eventable
    POSTMORTEM_COMPLETED if update.is_a?(PostmortemUpdate) && Array(update.changed_fields).include?("status") && update.status == Postmortem::STATUS_COMPLETED
  end
end
