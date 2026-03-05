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

  EVENT_TYPES = [
    INCIDENT_CREATED, INCIDENT_UPDATED, LEAD_ASSIGNED,
    ACTION_CREATED, ACTION_PICKED_UP, ACTION_COMPLETED,
    INCIDENT_ESCALATED, INCIDENT_RESOLVED, INCIDENT_REOPENED, POSTMORTEM_GENERATED
  ].freeze

  EVENT_DESCRIPTIONS = {
    INCIDENT_CREATED => "Incident was created",
    INCIDENT_UPDATED => "Incident was updated",
    LEAD_ASSIGNED => "Incident lead was assigned",
    ACTION_CREATED => "Action item was created",
    ACTION_PICKED_UP => "Action item was picked up",
    ACTION_COMPLETED => "Action item was completed",
    INCIDENT_ESCALATED => "Incident was escalated",
    INCIDENT_RESOLVED => "Incident was resolved",
    INCIDENT_REOPENED => "Incident was reopened",
    POSTMORTEM_GENERATED => "Postmortem was generated"
  }.freeze

  # Associations
  belongs_to :incident
  belongs_to :user, class_name: "WorkspaceMembership", optional: true
  delegated_type :eventable, types: %w[IncidentUpdate IncidentActionUpdate], optional: true

  # Callbacks
  after_create_commit :publish_to_event_bus

  # Validations
  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }

  # Scopes
  scope :chronological, -> { order(created_at: :asc) }
  scope :recent, -> { order(created_at: :desc) }
  scope :updates, -> { where(eventable_type: "IncidentUpdate") }
  scope :action_updates, -> { where(eventable_type: "IncidentActionUpdate") }

  # Helper methods
  def before_snapshot
    metadata["before"] || {}
  end

  def after_snapshot
    metadata["after"] || {}
  end

  def changed_fields
    if eventable.is_a?(IncidentUpdate) || eventable.is_a?(IncidentActionUpdate)
      eventable.changed_fields || []
    else
      metadata["changed_fields"] || []
    end
  end

  def details
    metadata["details"]
  end

  def changed?(field)
    changed_fields.include?(field.to_s)
  end

  def description
    EVENT_DESCRIPTIONS[event_type]
  end

  private

  def publish_to_event_bus
    ProcessDomainEventJob.perform_later(
      "event_type" => event_type,
      "incident_id" => incident_id,
      "user_id" => user_id,
      "data" => metadata,
      "occurred_at" => created_at.iso8601(6)
    )
  end
end
