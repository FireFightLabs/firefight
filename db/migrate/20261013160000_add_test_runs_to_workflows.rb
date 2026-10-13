class AddTestRunsToWorkflows < ActiveRecord::Migration[8.1]
  def change
    # What the run ran when that is not its version as it stands, a draft that changes or the steps up to one.
    add_column :workflow_runs, :snapshot, :jsonb
    # Outputs that stand in for steps, by step id, so they are not called again: pins and an earlier run's results.
    add_column :workflow_runs, :stand_ins, :jsonb, null: false, default: {}
    add_reference :workflow_runs, :rerun_of, type: :uuid, foreign_key: { to_table: :workflow_runs, on_delete: :nullify }
    add_column :workflow_runs, :rerun_from_step_key, :string

    # A step's output pinned on a draft, by step id, so test runs try later steps without calling it again.
    add_column :workflow_versions, :pins, :jsonb, null: false, default: {}

    # The run step a gateway call was made for, beside the run it already names, so a step lists its own calls and the
    # approvals it waits on. The step's own list of its calls goes, since the ledger now says it.
    add_column :ability_invocations, :workflow_step_key, :string
    add_column :ability_invocations, :workflow_iteration, :string
    add_index :ability_invocations, %i[workflow_run_id workflow_step_key], where: "workflow_run_id IS NOT NULL"
    remove_column :workflow_run_steps, :invocation_ids, :uuid, array: true, null: false, default: []
  end
end
