class IncidentUpdate < ApplicationRecord
  CREATED = "created"
  UPDATED = "updated"
  CLOSED = "closed"
  REOPENED = "reopened"
  LEAD_ASSIGNED = "lead_assigned"

  UPDATE_TYPES = [ CREATED, UPDATED, CLOSED, REOPENED, LEAD_ASSIGNED ].freeze

  has_one :incident_event, as: :eventable, touch: true

  belongs_to :incident
  belongs_to :workspace, optional: false
  belongs_to :incident_status
  belongs_to :incident_severity
  belongs_to :incident_type, optional: true
  belongs_to :declared_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :lead, class_name: "WorkspaceMembership", optional: true
  belongs_to :created_by, class_name: "WorkspaceMembership", optional: true

  validates :update_type, presence: true, inclusion: { in: UPDATE_TYPES }

  scope :ordered, -> { order(:created_at) }
  scope :communications, -> { where.not(message: [ nil, "" ]) }
  scope :by_type, ->(type) { where(update_type: type) }
end
