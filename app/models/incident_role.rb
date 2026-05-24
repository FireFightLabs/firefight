class IncidentRole < ApplicationRecord
  SLUG_INCIDENT_LEAD = "incident_lead"

  # Built-in roles the system depends on. The lead role is referenced by
  # name throughout the codebase (lead assignment, serializers, UI). No
  # workspace needs this seeded — `Workspace#ensure_incident_role!` creates
  # the row on first use when an assignment is made. Other roles a
  # workspace defines stay as regular DB rows with non-default slugs.
  DEFAULTS = [
    { name: "Incident Lead", slug: SLUG_INCIDENT_LEAD, position: 1, required: false, description: "Coordinates incident response and makes decisions" }
  ].freeze

  DEFAULTS_BY_SLUG = DEFAULTS.index_by { |d| d[:slug] }.freeze

  belongs_to :workspace
  has_many :incident_role_assignments, dependent: :destroy
  has_many :incidents, through: :incident_role_assignments

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validates :position, presence: true, numericality: { only_integer: true }

  scope :active, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position) }
  scope :incident_lead, -> { where(slug: SLUG_INCIDENT_LEAD) }

  def self.defaults_for(slug)
    DEFAULTS_BY_SLUG[slug]
  end

  # Merged list: code-default roles for slugs without a DB row (unpersisted)
  # plus any persisted custom roles. Used by the settings editor so the
  # lead role always appears even when no workspace customization exists.
  def self.all_for_workspace(workspace)
    persisted = workspace.incident_roles.active.to_a
    persisted_slugs = persisted.map(&:slug).to_set
    defaults_to_inject = DEFAULTS.reject { |d| persisted_slugs.include?(d[:slug]) }
    virtual = defaults_to_inject.map { |d| new(workspace: workspace, **d) }
    (persisted + virtual).sort_by(&:position)
  end

  def default_role?
    !persisted?
  end
end
