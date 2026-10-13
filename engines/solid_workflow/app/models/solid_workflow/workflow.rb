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
    # The step of another run that started this one, a sub workflow or one item of a for each.
    belongs_to :parent_step, class_name: "SolidWorkflow::Step", optional: true

    validates :name, :workflow_class, :subject_type, :subject_id, :state, presence: true
    validate :workflow_class_must_be_registered

    def workflow_klass
      @workflow_klass ||= SolidWorkflow::Base.registry[workflow_class]
    end

    # Whether its host lets it move now. A run held back keeps its place and moves again once let.
    def runnable? = workflow_klass.runnable?(self)

    def live? = pending? || running? || waiting?

    def definition_object(action_kinds: workflow_klass.action_kinds)
      SolidWorkflow::Definition.new(definition, action_kinds: action_kinds)
    end

    private

    def workflow_class_must_be_registered
      return if workflow_class.blank?
      return if SolidWorkflow::Base.registry.key?(workflow_class)

      errors.add(
        :workflow_class,
        "#{workflow_class} is not registered. " \
        "Workflow classes register themselves via `inherited`; ensure the file " \
        "(app/workflows/#{workflow_class.underscore}.rb) has been loaded — in " \
        "consoles without eager_load, run `Rails.application.eager_load!` or " \
        "`require_dependency '#{workflow_class.underscore}'` first."
      )
    end
  end
end
