# The app's one window onto SolidWorkflow's own records, for the operator console, which reads every run and acts on
# them. Everything else in the app reaches the engine through its workflow classes. Records come back as the engine's
# own, so their predicates and the engine's pause, resume, cancel, retry and skip are used as they are.
module WorkflowRuns
  STATES = SolidWorkflow::Workflow.states.keys.freeze
  STEP_STATUSES = SolidWorkflow::Step.statuses.keys.freeze
  FAILURE_EVENTS = [
    SolidWorkflow::Events::Workflow::FAILED, SolidWorkflow::Events::Step::FAILED, SolidWorkflow::Events::Step::ATTEMPT_FAILED
  ].freeze

  def self.recent(state: nil, kind: nil)
    scope = SolidWorkflow::Workflow.includes(:steps, :subject).order(created_at: :desc, id: :desc)
    scope = scope.where(state: state) if STATES.include?(state.to_s)
    kind.present? ? scope.where(workflow_class: kind) : scope
  end

  def self.kinds = SolidWorkflow::Workflow.distinct.order(:workflow_class).pluck(:workflow_class)

  def self.counts_by_state = SolidWorkflow::Workflow.group(:state).count

  def self.find(id) = SolidWorkflow::Workflow.includes(:steps, :subject, events: :step).find(id)

  def self.find_step(id) = SolidWorkflow::Step.includes(:workflow).find(id)

  def self.for_subject(subject) = SolidWorkflow::Workflow.where(subject: subject).includes(:steps)

  # How many steps failed, by the incident their workflow ran for.
  def self.failed_steps_by_incident(incident_ids)
    SolidWorkflow::Step.joins(:workflow).failed
                       .where(solid_workflow_workflows: { subject_type: Incident.name, subject_id: incident_ids })
                       .group("solid_workflow_workflows.subject_id").count
  end
end
