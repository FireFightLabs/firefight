class IncidentActionUpdate < ApplicationRecord
  CREATED = "created"
  PICKED_UP = "picked_up"
  COMPLETED = "completed"

  ACTION_UPDATE_TYPES = [ CREATED, PICKED_UP, COMPLETED ].freeze

  has_one :incident_event, as: :eventable, touch: true

  belongs_to :incident_action
  belongs_to :actor, class_name: "WorkspaceMembership"

  validates :action_update_type, presence: true, inclusion: { in: ACTION_UPDATE_TYPES }
  validates :action_type, presence: true, inclusion: { in: IncidentAction::ACTION_TYPES }

  scope :ordered, -> { order(:created_at) }
end
