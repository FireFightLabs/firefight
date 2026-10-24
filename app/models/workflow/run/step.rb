# What one step of a run did: its filled input, its output, the results it kept whole, its attempts and its time. A step
# inside a for each has one row per item, told apart by iteration, the item's place in each loop it sits in.
class Workflow::Run::Step < ApplicationRecord
  self.table_name = "workflow_run_steps"

  # The engine's step statuses, bypassed among them for a step on a route the run did not take.
  STATUSES = DefinedWorkflow::STEP_STATUSES
  STATUS_FAILED = DefinedWorkflow::STEP_FAILED
  STATUS_WAITING = DefinedWorkflow::STEP_WAITING
  STATUS_SUCCEEDED = DefinedWorkflow::STEP_SUCCEEDED
  # A step a run can be started again from: one that ended, or that never ran because the run stopped before it.
  RERUNNABLE = [
    DefinedWorkflow::STEP_SUCCEEDED, DefinedWorkflow::STEP_FAILED, DefinedWorkflow::STEP_SKIPPED, DefinedWorkflow::STEP_CANCELLED,
    DefinedWorkflow::STEP_PENDING
  ].freeze

  belongs_to :run, class_name: "Workflow::Run", inverse_of: :steps
  # Halon's chat for a step that asks it something, reads before a change or keeps a watch.
  has_one :chat, as: :owner, dependent: :destroy
  # What an Ask a person step asked, once per try.
  has_many :questions, class_name: "Workflow::Run::Question", foreign_key: :run_step_id, inverse_of: :run_step, dependent: :delete_all

  delegate :workspace_id, :workspace, :code_box_key, to: :run

  # What a watch the step keeps reads with. A run is never about an incident.
  def incident = nil
  def incident_id = nil

  validates :step_key, presence: true
  validates :status, inclusion: { in: STATUSES }

  def saved_results = run.saved_results.where(id: saved_result_ids)

  def top_level? = iteration.blank?

  # Why a step skipped itself, such as a change whose problem cleared before it ran, or nil.
  def note = (output.to_h[DefinedWorkflow::Steps::Base::OUTPUT_SKIPPED] if status == DefinedWorkflow::STEP_SKIPPED)

  # What a gateway call made for a run's step carries, so the ledger row names the run, the step and its for each item.
  def self.ledger_context(run, record)
    { workflow_run_id: run.id, workflow_step_key: record&.step_key, workflow_iteration: record&.iteration.presence }.compact
  end

  # What a gateway call made for this step carries, such as each read a watch it keeps makes.
  def ledger_context = self.class.ledger_context(run, self)

  # The gateway's record of each call the step made: what it called, whether it was allowed, held or refused, and how it
  # ended.
  def invocations
    Ability::Invocation.where(workflow_run_id: run_id, workflow_step_key: step_key, workflow_iteration: iteration.presence)
                       .includes(:approval).order(:created_at)
  end

  # Whether it is parked on an approval nobody has given yet.
  # The question an Ask a person step asked last.
  def asked_question = questions.order(:created_at).last

  # The request an Approval step asked last, which the run's page decides beside the Approvals page.
  def asked_approval
    Ability::Approval.where(workspace_id: workspace_id, workflow_run_id: run_id, action_key: Ability::Action::WORKFLOW_APPROVAL)
                     .where("params ->> 'run_step_id' = ?", id).order(:created_at).last
  end

  def waiting_approval?
    status == STATUS_WAITING && invocations.any? { |call| call.decision == Ability::Invocation::DECISION_PENDING && call.approval&.pending? }
  end

  def retry_blocked_reason
    return "This run's details were let go, so its steps cannot be tried again." if run.details_pruned?
    return "Only a step that failed can be tried again." unless status == STATUS_FAILED

    nil
  end

  def skip_blocked_reason
    return "This run's details were let go, so its steps cannot be skipped." if run.details_pruned?
    return "Only a step that failed or is waiting can be skipped." unless [ STATUS_FAILED, STATUS_WAITING ].include?(status)

    nil
  end

  # Why the run cannot start again from this step, as a sentence, or nil.
  def rerun_blocked_reason
    return "A run starts again from a top level step, so start it from the for each this step sits in." unless top_level?
    return "This run's details were let go, so it cannot start again from a step." if run.details_pruned?
    return "Wait for this step to finish before starting again from it." unless RERUNNABLE.include?(status)

    run.workflow.start_blocked_reason unless run.test?
  end
end
