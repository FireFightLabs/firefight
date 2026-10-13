module SolidWorkflow
  class Step < Record
    include Step::Statusable
    include Step::Executable
    include Step::Retryable
    include Step::Dependencies
    include Step::Routing
    include Step::Waitable
    include Step::Metrics

    belongs_to :workflow, class_name: "SolidWorkflow::Workflow"
    has_many :events, class_name: "SolidWorkflow::Event", foreign_key: :step_id, dependent: :destroy
    # Runs this step started, a sub workflow or one per item of a for each.
    has_many :children, class_name: "SolidWorkflow::Workflow", foreign_key: :parent_step_id, inverse_of: :parent_step

    validates :name, :status, presence: true

    scope :ordered, -> { order(:position) }

    def queue_name
      retry_config&.dig("queue").presence || SolidWorkflow.queue_name.to_s
    end
  end
end
