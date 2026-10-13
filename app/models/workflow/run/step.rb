# What one step of a run did: its filled input, its output, the results it kept whole, its attempts and its time. A step
# inside a for each has one row per item, told apart by iteration, the item's place in each loop it sits in.
class Workflow::Run::Step < ApplicationRecord
  self.table_name = "workflow_run_steps"

  # The engine's step statuses, bypassed among them for a step on a route the run did not take.
  STATUSES = DefinedWorkflow::STEP_STATUSES
  STATUS_SUCCEEDED = STATUSES.fetch(STATUSES.index("succeeded"))
  STATUS_FAILED = STATUSES.fetch(STATUSES.index("failed"))
  STATUS_WAITING = STATUSES.fetch(STATUSES.index("waiting"))

  belongs_to :run, class_name: "Workflow::Run", inverse_of: :steps
  # Halon's chat for a step that asks it something, reads before a change or keeps a watch.
  has_one :chat, as: :owner, dependent: :destroy

  delegate :workspace_id, :workspace, :code_box_key, to: :run

  # What a watch the step keeps reads with. A run is never about an incident.
  def incident = nil
  def incident_id = nil

  validates :step_key, presence: true
  validates :status, inclusion: { in: STATUSES }

  def saved_results = run.saved_results.where(id: saved_result_ids)
end
