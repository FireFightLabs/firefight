class IncidentRelationship < ApplicationRecord
  RELATED = "related"
  DUPLICATE = "duplicate"
  RELATIONSHIP_TYPES = [ RELATED, DUPLICATE ].freeze

  belongs_to :incident
  belongs_to :related_incident, class_name: "Incident"
  belongs_to :created_by, polymorphic: true, optional: true

  validates :relationship_type, presence: true, inclusion: { in: RELATIONSHIP_TYPES }
  # Mirrors the chk_no_self_reference constraint. Without it the database
  # refuses the row as a 500 rather than a sentence.
  validate :not_itself
  validate :incidents_in_same_workspace
  validate :no_duplicate_loop, if: -> { relationship_type == DUPLICATE }
  validate :no_reverse_duplicate, if: -> { relationship_type == DUPLICATE }

  scope :related, -> { where(relationship_type: RELATED) }
  scope :duplicates, -> { where(relationship_type: DUPLICATE) }

  private

  def not_itself
    return unless incident_id && incident_id == related_incident_id

    errors.add(:related_incident, "must be a different incident")
  end

  def incidents_in_same_workspace
    return unless incident && related_incident
    return if incident.workspace_id == related_incident.workspace_id

    errors.add(:related_incident, "must belong to the same workspace")
  end

  def no_duplicate_loop
    return unless incident_id && related_incident_id

    if IncidentRelationship.duplicates.exists?(incident_id: related_incident_id, related_incident_id: incident_id)
      errors.add(:base, "cannot create circular duplicate relationship")
    end
  end

  def no_reverse_duplicate
    return unless incident_id && related_incident_id

    if IncidentRelationship.duplicates.exists?(incident_id: incident_id, related_incident_id: related_incident_id)
      errors.add(:base, "duplicate relationship already exists")
    end
  end
end
