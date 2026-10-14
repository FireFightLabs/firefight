# How many runs a workflow may start in an hour is its own setting, 100 unless someone sets another, and no longer a
# ceiling the whole workspace shares for runs an event starts. A run a trigger would have started past it is counted
# by the hour it was skipped in, so the workflow's page says how many and when.
class MoveEventRunsPerHourOntoWorkflows < ActiveRecord::Migration[8.1]
  def change
    change_column_default :workflows, :runs_per_hour, from: 60, to: 100
    remove_column :workspaces, :workflow_event_runs_per_hour, :integer, null: false, default: 100

    create_table :workflow_skipped_runs, id: :uuid do |t|
      t.references :workflow, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.datetime :hour, null: false
      t.integer :count, null: false, default: 0
      t.datetime :last_at, null: false
      t.timestamps
    end
    add_index :workflow_skipped_runs, [ :workflow_id, :hour ], unique: true
  end
end
