class IncidentLifecycleStage < ApplicationRecord
  TRIAGE = "triage"
  ACTIVE = "active"
  CLOSED = "closed"
  CANCELED = "canceled"

  KEYS = [ TRIAGE, ACTIVE, CLOSED, CANCELED ].freeze

  has_many :incident_statuses, dependent: :restrict_with_error

  validates :key, presence: true, uniqueness: true, inclusion: { in: KEYS }
  validates :name, presence: true
  validates :description, presence: true
  validates :position, presence: true

  scope :ordered, -> { order(:position) }

  def triage?
    key == TRIAGE
  end

  def active?
    key == ACTIVE
  end

  def closed?
    key == CLOSED
  end

  def canceled?
    key == CANCELED
  end

  def open?
    triage? || active?
  end
end
