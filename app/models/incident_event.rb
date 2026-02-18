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

  # Associations
  belongs_to :incident
  belongs_to :user, class_name: "WorkspaceMembership", optional: true

  # Validations
  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }

  # Scopes
  scope :chronological, -> { order(created_at: :asc) }
  scope :recent, -> { order(created_at: :desc) }

  # Helper methods
  def before_snapshot
    metadata["before"] || {}
  end

  def after_snapshot
    metadata["after"] || {}
  end

  def changed_fields
    metadata["changed_fields"] || []
  end

  def details
    metadata["details"]
  end

  def changed?(field)
    changed_fields.include?(field.to_s)
  end
end
