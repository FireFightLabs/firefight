class IncidentUpdate < ApplicationRecord
  CREATED = "created"
  UPDATED = "updated"
  CLOSED = "closed"
  REOPENED = "reopened"
  LEAD_ASSIGNED = "lead_assigned"
  ACCEPTED = "accepted"
  CANCELED = "canceled"

  UPDATE_TYPES = [ CREATED, UPDATED, CLOSED, REOPENED, LEAD_ASSIGNED, ACCEPTED, CANCELED ].freeze

  include Recordable
  include Changes

  # Set by Incident#timeline_events from one ordered load, so a timeline
  # never runs a query per update to find what came before it.
  attr_accessor :previous_update
  records Incident, recorder: :created_by

  belongs_to :incident
  belongs_to :workspace, optional: false
  belongs_to :incident_status
  belongs_to :incident_severity
  belongs_to :incident_type, optional: true
  belongs_to :declared_by, polymorphic: true, optional: true
  belongs_to :lead, class_name: "WorkspaceMembership", optional: true
  belongs_to :created_by, polymorphic: true, optional: true

  validates :update_type, presence: true, inclusion: { in: UPDATE_TYPES }

  scope :ordered, -> { order(:created_at) }
  scope :communications, -> { where.not(message: [ nil, "" ]) }
  scope :by_type, ->(type) { where(update_type: type) }
end
