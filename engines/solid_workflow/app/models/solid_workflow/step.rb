module SolidWorkflow
  class Step < Record
    include Step::Statusable
    include Step::Executable
    include Step::Retryable
    include Step::Dependencies
    include Step::Metrics

    belongs_to :workflow, class_name: "SolidWorkflow::Workflow"
    has_many :events, class_name: "SolidWorkflow::Event", foreign_key: :step_id, dependent: :destroy

    validates :name, :status, presence: true

    scope :ordered, -> { order(:position) }

    def queue_name
      retry_config&.dig("queue").presence || SolidWorkflow.queue_name.to_s
    end
  end
end
