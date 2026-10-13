# What one step of a run did: its filled input, its output, the results it kept whole, its attempts and its time. A step
# inside a for each has one row per item, told apart by iteration, the item's place in each loop it sits in.
class Workflow::Run::Step < ApplicationRecord
  self.table_name = "workflow_run_steps"

  # The engine's step statuses, bypassed among them for a step on a route the run did not take.
  STATUSES = DefinedWorkflow::STEP_STATUSES

  belongs_to :run, class_name: "Workflow::Run", inverse_of: :steps

  validates :step_key, presence: true
  validates :status, inclusion: { in: STATUSES }

  def saved_results = run.saved_results.where(id: saved_result_ids)
end
