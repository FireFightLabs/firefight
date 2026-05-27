class IncidentStatus < ApplicationRecord
  include Positioned

  belongs_to :workspace
  belongs_to :incident_lifecycle_stage

  has_many :incidents, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validates :position, presence: true, numericality: { only_integer: true }
  validates :is_default, uniqueness: { scope: :workspace_id, if: :is_default? }

  scope :active, -> { where(deleted_at: nil) }
  scope :triage, -> { joins(:incident_lifecycle_stage).where(incident_lifecycle_stages: { key: IncidentLifecycleStage::TRIAGE }) }
  scope :live, -> { joins(:incident_lifecycle_stage).where(incident_lifecycle_stages: { key: [ IncidentLifecycleStage::TRIAGE, IncidentLifecycleStage::ACTIVE ] }) }
  scope :closed, -> { joins(:incident_lifecycle_stage).where(incident_lifecycle_stages: { key: IncidentLifecycleStage::CLOSED }) }
  scope :canceled, -> { joins(:incident_lifecycle_stage).where(incident_lifecycle_stages: { key: IncidentLifecycleStage::CANCELED }) }
  scope :ordered, -> { order(:position) }
  scope :default_status, -> { active.find_by(is_default: true) }

  delegate :triage?, :active?, :closed?, :canceled?, to: :incident_lifecycle_stage

  def live?
    triage? || active?
  end
end
