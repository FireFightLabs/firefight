class IncidentAction < ApplicationRecord
  include IncidentAction::Snapshots

  ACTION_TYPE_ACTION = "action"
  ACTION_TYPE_FOLLOWUP = "followup"
  ACTION_TYPES = [ ACTION_TYPE_ACTION, ACTION_TYPE_FOLLOWUP ].freeze

  STATUS_OPEN = "open"
  STATUS_IN_PROGRESS = "in_progress"
  STATUS_DONE = "done"
  STATUSES = [ STATUS_OPEN, STATUS_IN_PROGRESS, STATUS_DONE ].freeze

  belongs_to :incident
  belongs_to :created_by, class_name: "WorkspaceMembership"
  belongs_to :assignee, class_name: "WorkspaceMembership", optional: true
  has_many :incident_action_updates, dependent: :destroy

  validates :action_type, inclusion: { in: ACTION_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :description, presence: true

  scope :active, -> { where(deleted_at: nil) }
  scope :actions, -> { where(action_type: ACTION_TYPE_ACTION) }
  scope :followups, -> { where(action_type: ACTION_TYPE_FOLLOWUP) }
  scope :open, -> { where(status: STATUS_OPEN) }
  scope :completed, -> { where(status: STATUS_DONE) }
  scope :recent, -> { order(created_at: :desc) }

  def open?
    status == STATUS_OPEN
  end

  def done?
    status == STATUS_DONE
  end

  def assigned?
    assignee_id.present?
  end
end
