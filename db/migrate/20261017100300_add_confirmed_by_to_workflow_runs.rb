# The person who confirmed a run Halon started for them in a chat, whose yes also answers a step an approval rule would
# ask them about, so nobody is asked twice for one run.
class AddConfirmedByToWorkflowRuns < ActiveRecord::Migration[8.1]
  def change
    add_reference :workflow_runs, :confirmed_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
  end
end
