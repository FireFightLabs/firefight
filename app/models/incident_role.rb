class IncidentRole < ApplicationRecord
  SLUG_INCIDENT_LEAD = "incident_lead"

  belongs_to :workspace
  has_many :incident_role_assignments, dependent: :destroy
  has_many :incidents, through: :incident_role_assignments

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validates :position, presence: true, numericality: { only_integer: true }

  scope :active, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position) }
  scope :incident_lead, -> { where(slug: SLUG_INCIDENT_LEAD) }
end
