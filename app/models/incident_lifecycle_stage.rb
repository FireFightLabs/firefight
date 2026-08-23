class IncidentLifecycleStage < ApplicationRecord
  TRIAGE = "triage"
  ACTIVE = "active"
  CLOSED = "closed"
  CANCELED = "canceled"

  KEYS = [ TRIAGE, ACTIVE, CLOSED, CANCELED ].freeze

  # The four global rows, defined once for the migration-era seed and
  # db/seeds.rb alike. Idempotent.
  DEFAULTS = [
    { key: TRIAGE, name: "Triage", description: "Potential incident under investigation, not yet confirmed as active.", position: 1 },
    { key: ACTIVE, name: "Active", description: "Confirmed incident actively being worked by responders.", position: 2 },
    { key: CLOSED, name: "Closed", description: "Incident resolved and no longer actively managed.", position: 3 },
    { key: CANCELED, name: "Canceled", description: "False positive, duplicate, or invalid incident. Excluded from resolved metrics.", position: 4 }
  ].freeze

  def self.seed!
    DEFAULTS.each do |attrs|
      find_or_create_by!(key: attrs[:key]) { |stage| stage.assign_attributes(attrs.except(:key)) }
    end
  end

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
