class IncidentActionUpdate < ApplicationRecord
  CREATED = "created"
  PICKED_UP = "picked_up"
  COMPLETED = "completed"

  UPDATE_TYPES = [ CREATED, PICKED_UP, COMPLETED ].freeze

  include Recordable
  records IncidentAction, recorder: :actor

  belongs_to :incident_action
  belongs_to :incident
  belongs_to :actor, polymorphic: true
  belongs_to :created_by, class_name: "WorkspaceMembership"
  belongs_to :assignee, class_name: "WorkspaceMembership", optional: true

  validates :update_type, presence: true, inclusion: { in: UPDATE_TYPES }
  validates :action_type, presence: true, inclusion: { in: ->(_) { IncidentAction::ACTION_TYPES } }
  validates :description, presence: true
  validates :status, presence: true, inclusion: { in: ->(_) { IncidentAction::STATUSES } }

  scope :ordered, -> { order(:created_at) }
  scope :by_type, ->(type) { where(update_type: type) }
end
