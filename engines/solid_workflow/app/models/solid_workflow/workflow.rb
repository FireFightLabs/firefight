module SolidWorkflow
  class Workflow < Record
    include Workflow::Stateable
    include Workflow::Eventable
    include Workflow::Orchestratable
    include Workflow::Cancellable
    include Workflow::Pausable
    include Workflow::Metrics

    belongs_to :subject, polymorphic: true
    has_many :steps, -> { order(:position) }, class_name: "SolidWorkflow::Step", dependent: :destroy
    has_many :events, class_name: "SolidWorkflow::Event", dependent: :destroy

    validates :name, :workflow_class, :subject_type, :subject_id, :state, presence: true
    validate :workflow_class_must_be_registered

    def workflow_klass
      @workflow_klass ||= SolidWorkflow::Base.registry[workflow_class]
    end

    private

    def workflow_class_must_be_registered
      return if workflow_class.blank?

      unless SolidWorkflow::Base.registry.key?(workflow_class)
        errors.add(:workflow_class, "must be a registered workflow class (#{workflow_class} not found in registry)")
      end
    end
  end
end
