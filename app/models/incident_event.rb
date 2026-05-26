class IncidentEvent < ApplicationRecord
  # Event type constants
  INCIDENT_CREATED = "incident.created"
  INCIDENT_UPDATED = "incident.updated"
  LEAD_ASSIGNED = "lead.assigned"
  ACTION_CREATED = "action.created"
  ACTION_PICKED_UP = "action.picked_up"
  ACTION_COMPLETED = "action.completed"
  INCIDENT_ESCALATED = "incident.escalated"
  INCIDENT_RESOLVED = "incident.resolved"
  INCIDENT_REOPENED = "incident.reopened"
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

  EVENT_TYPES = [
    INCIDENT_CREATED, INCIDENT_UPDATED, INCIDENT_ACCEPTED, LEAD_ASSIGNED,
    ACTION_CREATED, ACTION_PICKED_UP, ACTION_COMPLETED,
    INCIDENT_ESCALATED, INCIDENT_RESOLVED, INCIDENT_REOPENED, POSTMORTEM_GENERATED, POSTMORTEM_EDITED,
    RELATIONSHIP_CREATED, MARKED_DUPLICATE, MERGED_INTO,
    MESSAGE_PINNED, MESSAGE_UNPINNED, MESSAGE_FILE_SHARED,
    ESCALATION_ACKNOWLEDGED, ESCALATION_NUDGED
  ].freeze

  EVENT_DESCRIPTIONS = {
    INCIDENT_CREATED => "Incident was created",
    INCIDENT_UPDATED => "Incident was updated",
    LEAD_ASSIGNED => "Incident lead was assigned",
    ACTION_CREATED => "Action item was created",
    ACTION_PICKED_UP => "Action item was picked up",
    ACTION_COMPLETED => "Action item was completed",
    INCIDENT_ACCEPTED => "Incident was accepted from triage",
    INCIDENT_ESCALATED => "Incident was escalated",
    INCIDENT_RESOLVED => "Incident was resolved",
    INCIDENT_REOPENED => "Incident was reopened",
    POSTMORTEM_GENERATED => "Postmortem was generated",
    POSTMORTEM_EDITED => "Postmortem was edited",
    RELATIONSHIP_CREATED => "Incident linked as related",
    MARKED_DUPLICATE => "Incident marked as duplicate",
    MERGED_INTO => "Incident merged into another",
    MESSAGE_PINNED => "Message was pinned",
    MESSAGE_UNPINNED => "Message was unpinned",
    MESSAGE_FILE_SHARED => "File was shared",
    ESCALATION_ACKNOWLEDGED => "Escalation was acknowledged",
    ESCALATION_NUDGED => "Escalation reminder was sent"
  }.freeze

  # Canonical event_type -> recordable update_type map. Only events backed by
  # a Recordable snapshot (IncidentUpdate/IncidentActionUpdate/PostmortemUpdate)
  # appear here. Action-only events (pins, file shares, escalations,
  # relationships) carry their payload in `metadata` and have no eventable.
  UPDATE_TYPE_MAP = {
    INCIDENT_CREATED     => IncidentUpdate::CREATED,
    INCIDENT_UPDATED     => IncidentUpdate::UPDATED,
    INCIDENT_ACCEPTED    => IncidentUpdate::ACCEPTED,
    LEAD_ASSIGNED        => IncidentUpdate::LEAD_ASSIGNED,
    INCIDENT_RESOLVED    => IncidentUpdate::CLOSED,
    INCIDENT_REOPENED    => IncidentUpdate::REOPENED,
    MERGED_INTO          => IncidentUpdate::CLOSED,
    ACTION_CREATED       => IncidentActionUpdate::CREATED,
    ACTION_PICKED_UP     => IncidentActionUpdate::PICKED_UP,
    ACTION_COMPLETED     => IncidentActionUpdate::COMPLETED,
    POSTMORTEM_GENERATED => PostmortemUpdate::GENERATED,
    POSTMORTEM_EDITED    => PostmortemUpdate::EDITED
  }.freeze

  def self.update_type_for(event_type)
    UPDATE_TYPE_MAP.fetch(event_type) do
      raise ArgumentError, "no recordable update_type for event_type=#{event_type.inspect}"
    end
  end

  # Associations
  belongs_to :incident
  belongs_to :user, class_name: "WorkspaceMembership", optional: true
  delegated_type :eventable, types: %w[IncidentUpdate IncidentActionUpdate PostmortemUpdate], optional: true
  has_one_attached :artifact

  after_create_commit :publish_to_event_bus

  # Validations
  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }

  # Scopes
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

  def description
    EVENT_DESCRIPTIONS[event_type]
  end

  def to_context_hash
    { type: event_type, at: created_at.iso8601, by: user&.user&.name, description: description }
  end

  private

  def publish_to_event_bus
    ProcessDomainEventJob.perform_later(
      "event_id" => id,
      "event_type" => event_type,
      "incident_id" => incident_id,
      "user_id" => user_id,
      "data" => metadata,
      "occurred_at" => created_at.iso8601(6)
    )
  end
end
