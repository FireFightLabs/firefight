class IncidentUpdate < ApplicationRecord
  CREATED = "created"
  UPDATED = "updated"
  CLOSED = "closed"
  REOPENED = "reopened"
  LEAD_ASSIGNED = "lead_assigned"
  ACCEPTED = "accepted"

  UPDATE_TYPES = [ CREATED, UPDATED, CLOSED, REOPENED, LEAD_ASSIGNED, ACCEPTED ].freeze

  include Recordable
  records Incident, recorder: :created_by

  belongs_to :incident
  belongs_to :workspace, optional: false
  belongs_to :incident_status
  belongs_to :incident_severity
  belongs_to :incident_type, optional: true
  belongs_to :declared_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :lead, class_name: "WorkspaceMembership", optional: true
  belongs_to :created_by, polymorphic: true, optional: true

  validates :update_type, presence: true, inclusion: { in: UPDATE_TYPES }

  scope :ordered, -> { order(:created_at) }
  scope :communications, -> { where.not(message: [ nil, "" ]) }
  scope :by_type, ->(type) { where(update_type: type) }

  def display_value_for(field)
    case field.to_s
    when "status"   then incident_status&.name
    when "severity" then incident_severity&.name
    when "type"     then incident_type&.name
    when "lead"     then lead&.actor_display_name
    when "declared_by" then declared_by&.actor_display_name
    else
      return nil unless respond_to?(field)
      public_send(field).to_s
    end
  end
end
