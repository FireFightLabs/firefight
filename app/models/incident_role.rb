class IncidentRole < ApplicationRecord
  belongs_to :workspace
  has_many :incident_role_assignments, dependent: :destroy
  has_many :incidents, through: :incident_role_assignments

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validates :position, presence: true, numericality: { only_integer: true }

  scope :ordered, -> { order(:position) }
  scope :required_roles, -> { where(required: true) }

  def self.incident_lead
    find_by(slug: "incident_lead")
  end
end
