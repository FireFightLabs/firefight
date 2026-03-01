module SolidWorkflow
  class Event < Record
    belongs_to :workflow, class_name: "SolidWorkflow::Workflow"
    belongs_to :step, class_name: "SolidWorkflow::Step", optional: true

    validates :event_type, presence: true

    scope :workflow_level, -> { where(step_id: nil) }
    scope :step_level, -> { where.not(step_id: nil) }
  end
end
