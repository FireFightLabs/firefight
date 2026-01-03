class WorkflowEvent < ApplicationRecord
  belongs_to :workflow
  belongs_to :workflow_step, optional: true

  validates :event_type, presence: true


  scope :workflow_level, -> { where(workflow_step_id: nil) }
  scope :step_level, -> { where.not(workflow_step_id: nil) }
end
