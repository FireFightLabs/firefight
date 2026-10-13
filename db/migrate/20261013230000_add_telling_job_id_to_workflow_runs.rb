# Which job is telling how a run ended, so told_at is written only once it was told and a job its stopped worker left
# can take its own claim back when it runs again.
class AddTellingJobIdToWorkflowRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :workflow_runs, :telling_job_id, :string
  end
end
