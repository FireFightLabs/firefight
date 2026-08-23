class IncidentRole < ApplicationRecord
  include ConfigurableOption

  NOUN = "role".freeze
  SLUG_INCIDENT_LEAD = "incident_lead"

  # The lead role is referenced by slug throughout the codebase (lead
  # assignment, serializers, UI), so every workspace gets a real row for it.
  DEFAULTS = [
    { name: "Incident Lead", slug: SLUG_INCIDENT_LEAD, position: 1, required: false, description: "Coordinates incident response and makes decisions." }
  ].freeze

  DEFAULTS_BY_SLUG = DEFAULTS.index_by { |d| d[:slug] }.freeze

  # Assignments are join records, so they follow the role. Deleting a role in
  # use is stopped by deletion_blocked_reason, not by the association.
  has_many :incident_role_assignments, dependent: :destroy
  has_many :incidents, through: :incident_role_assignments

  scope :incident_lead, -> { where(slug: SLUG_INCIDENT_LEAD) }

  def self.usage_association
    :incident_role_assignments
  end

  def self.defaults_for(slug)
    DEFAULTS_BY_SLUG[slug]
  end

  def system?
    slug == SLUG_INCIDENT_LEAD
  end

  def deletion_blocked_reason
    return "The Incident Lead role is built in and cannot be deleted." if system?

    super
  end

  def disable_blocked_reason
    return "The Incident Lead role is built in and cannot be disabled." if system?

    super
  end

  # An incident that has had a lead keeps one. Handing over is a reassignment,
  # never a gap in who is accountable.
  def unassign_blocked_reason
    return "The Incident Lead cannot be cleared. Assign someone else instead." if system?

    nil
  end
end
