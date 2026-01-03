class WorkflowStep < ApplicationRecord
  include WorkflowStep::Statusable
  include WorkflowStep::Executable
  include WorkflowStep::Retryable
  include WorkflowStep::Dependencies
  include WorkflowStep::Metrics

  belongs_to :workflow
  has_many :workflow_events, dependent: :destroy

  validates :name, :status, presence: true

  scope :ordered, -> { order(:position) }
end
