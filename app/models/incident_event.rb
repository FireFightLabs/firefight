class IncidentEvent < ApplicationRecord
  INCIDENT_CREATED = "incident.created"
  INCIDENT_UPDATED = "incident.updated"
  LEAD_ASSIGNED = "lead.assigned"
  ROLE_ASSIGNED = "role.assigned"
  ROLE_UNASSIGNED = "role.unassigned"
  ACTION_CREATED = "action.created"
  ACTION_PICKED_UP = "action.picked_up"
  ACTION_COMPLETED = "action.completed"
  ACTION_REASSIGNED = "action.reassigned"
  INCIDENT_ESCALATED = "incident.escalated"
  INCIDENT_RESOLVED = "incident.resolved"
  INCIDENT_REOPENED = "incident.reopened"
  INCIDENT_CANCELED = "incident.canceled"
  POSTMORTEM_GENERATED = "postmortem.generated"
  POSTMORTEM_EDITED = "postmortem.edited"
  RELATIONSHIP_CREATED = "relationship.created"
  MARKED_DUPLICATE = "incident.marked_duplicate"
  MERGED_INTO = "incident.merged_into"
  MESSAGE_PINNED = "message.pinned"
  MESSAGE_UNPINNED = "message.unpinned"
  MESSAGE_FILE_SHARED = "message.file_shared"
  INCIDENT_ACCEPTED = "incident.accepted"
  ESCALATION_ACKNOWLEDGED = "incident.escalation_acknowledged"
  ESCALATION_NUDGED = "incident.escalation_nudged"
  ALERT_ATTACHED = "alert.attached"
  ALERT_RESOLVED = "alert.resolved"
  RUNBOOK_ATTACHED = "runbook.attached"
  RUNBOOK_APPLIED = "runbook.applied"

  EVENT_TYPES = [
    INCIDENT_CREATED, INCIDENT_UPDATED, INCIDENT_ACCEPTED, LEAD_ASSIGNED,
    ROLE_ASSIGNED, ROLE_UNASSIGNED,
    ACTION_CREATED, ACTION_PICKED_UP, ACTION_COMPLETED, ACTION_REASSIGNED,
    INCIDENT_ESCALATED, INCIDENT_RESOLVED, INCIDENT_REOPENED, INCIDENT_CANCELED, POSTMORTEM_GENERATED, POSTMORTEM_EDITED,
    RELATIONSHIP_CREATED, MARKED_DUPLICATE, MERGED_INTO,
    MESSAGE_PINNED, MESSAGE_UNPINNED, MESSAGE_FILE_SHARED,
    ESCALATION_ACKNOWLEDGED, ESCALATION_NUDGED,
    ALERT_ATTACHED, ALERT_RESOLVED,
    RUNBOOK_ATTACHED, RUNBOOK_APPLIED
  ].freeze

  EVENT_DESCRIPTIONS = {
    INCIDENT_CREATED => "created the incident",
    INCIDENT_UPDATED => "updated the incident",
    LEAD_ASSIGNED => "assigned a lead",
    ROLE_ASSIGNED => "assigned an incident role",
    ROLE_UNASSIGNED => "cleared an incident role",
    ACTION_CREATED => "created an action item",
    ACTION_PICKED_UP => "picked up an action item",
    ACTION_COMPLETED => "completed an action item",
    ACTION_REASSIGNED => "reassigned an action item",
    INCIDENT_ACCEPTED => "accepted the incident from triage",
    INCIDENT_ESCALATED => "escalated the incident",
    INCIDENT_RESOLVED => "resolved the incident",
    INCIDENT_REOPENED => "reopened the incident",
    INCIDENT_CANCELED => "canceled the incident",
    POSTMORTEM_GENERATED => "generated the postmortem",
    POSTMORTEM_EDITED => "edited the postmortem",
    RELATIONSHIP_CREATED => "linked a related incident",
    MARKED_DUPLICATE => "marked the incident as duplicate",
    MERGED_INTO => "merged the incident",
    MESSAGE_PINNED => "pinned a message",
    MESSAGE_UNPINNED => "unpinned a message",
    MESSAGE_FILE_SHARED => "shared a file",
    ESCALATION_ACKNOWLEDGED => "acknowledged the escalation",
    ESCALATION_NUDGED => "sent an escalation reminder",
    ALERT_ATTACHED => "attached an alert",
    ALERT_RESOLVED => "marked an alert resolved",
    RUNBOOK_ATTACHED => "attached a runbook",
    RUNBOOK_APPLIED => "added runbook steps as actions"
  }.freeze

  # Only events backed by a Recordable snapshot appear here. Action-only events
  # (pins, file shares, escalations, relationships) carry their payload in
  # `metadata` and have no eventable.
  UPDATE_TYPE_MAP = {
    INCIDENT_CREATED     => IncidentUpdate::CREATED,
    INCIDENT_UPDATED     => IncidentUpdate::UPDATED,
    INCIDENT_ACCEPTED    => IncidentUpdate::ACCEPTED,
    LEAD_ASSIGNED        => IncidentUpdate::LEAD_ASSIGNED,
    INCIDENT_RESOLVED    => IncidentUpdate::CLOSED,
    INCIDENT_REOPENED    => IncidentUpdate::REOPENED,
    INCIDENT_CANCELED    => IncidentUpdate::CANCELED,
    MERGED_INTO          => IncidentUpdate::CLOSED,
    ACTION_CREATED       => IncidentActionUpdate::CREATED,
    ACTION_PICKED_UP     => IncidentActionUpdate::PICKED_UP,
    ACTION_COMPLETED     => IncidentActionUpdate::COMPLETED,
    ACTION_REASSIGNED    => IncidentActionUpdate::REASSIGNED,
    POSTMORTEM_GENERATED => PostmortemUpdate::GENERATED,
    POSTMORTEM_EDITED    => PostmortemUpdate::EDITED
  }.freeze

  def self.update_type_for(event_type)
    UPDATE_TYPE_MAP.fetch(event_type) do
      raise ArgumentError, "no recordable update_type for event_type=#{event_type.inspect}"
    end
  end

  belongs_to :incident
  belongs_to :actor, polymorphic: true, optional: true
  delegated_type :eventable, types: %w[IncidentUpdate IncidentActionUpdate PostmortemUpdate], optional: true
  has_one_attached :artifact

  after_create_commit :publish_to_event_bus

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validate :eventable_matches_event_type

  scope :chronological, -> { order(created_at: :asc) }
  scope :recent, -> { order(created_at: :desc) }
  scope :updates, -> { where(eventable_type: "IncidentUpdate") }
  scope :action_updates, -> { where(eventable_type: "IncidentActionUpdate") }
  scope :postmortem_updates, -> { where(eventable_type: "PostmortemUpdate") }

  def changed_fields
    eventable&.changed_fields || []
  end

  def changed?(field = nil)
    return super() if field.nil?

    changed_fields.include?(field.to_s)
  end

  # Role events name the role and the person, since they carry no snapshot to
  # render a before/after from, and "assigned an incident role" on its own
  # leaves out the only two facts a reader wants.
  def description
    role_name = metadata.to_h["role_name"]
    return EVENT_DESCRIPTIONS[event_type] if role_name.blank?

    case event_type
    when ROLE_ASSIGNED then role_assigned_description(role_name)
    when ROLE_UNASSIGNED then "cleared the #{role_name} role"
    else EVENT_DESCRIPTIONS[event_type]
    end
  end

  def to_context_hash
    { type: event_type, at: created_at.iso8601, by: actor&.actor_display_name, description: description }
  end

  private

  def role_assigned_description(role_name)
    member_name = metadata.to_h["member_name"]
    return "assigned the #{role_name} role" if member_name.blank?

    "assigned the #{role_name} role to #{member_name}"
  end

  def eventable_matches_event_type
    return if event_type.blank?

    snapshot_backed = UPDATE_TYPE_MAP.key?(event_type)

    if snapshot_backed && eventable.nil?
      errors.add(:eventable, "is required for event_type=#{event_type}")
    elsif !snapshot_backed && eventable.present?
      errors.add(:eventable, "must be nil for event_type=#{event_type}")
    end
  end

  def publish_to_event_bus
    ProcessDomainEventJob.perform_later(
      "event_id" => id,
      "event_type" => event_type,
      "incident_id" => incident_id,
      "actor_type" => actor_type,
      "actor_id" => actor_id,
      "data" => metadata,
      "occurred_at" => created_at.iso8601(6)
    )
  end
end
