class CreateInvestigationRegression < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :halon_regression_enabled, :boolean, null: false, default: false

    create_table :investigation_regression_runs, id: :uuid do |t|
      t.string :trigger, null: false
      t.string :prompt_version, null: false
      t.string :model
      t.string :provider
      t.string :status, null: false, default: "running"
      t.references :started_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :finished_at
      t.timestamps
    end
    add_index :investigation_regression_runs, :created_at
    # A prompt version is tested on its own once, however many workers notice it at the same moment.
    add_index :investigation_regression_runs, :prompt_version, unique: true, where: "trigger = 'prompt_change'",
                                                               name: "index_regression_runs_one_per_prompt_change"

    create_table :investigation_regression_results, id: :uuid do |t|
      t.references :regression_run, type: :uuid, null: false, foreign_key: { to_table: :investigation_regression_runs, on_delete: :cascade }
      t.references :finding, type: :uuid, null: false, foreign_key: { to_table: :investigation_findings, on_delete: :cascade }
      t.references :replay, type: :uuid, foreign_key: { to_table: :investigations, on_delete: :nullify }
      t.string :expected, null: false
      t.string :status, null: false, default: "pending"
      t.text :answer
      t.text :reason
      t.bigint :spent_micros, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :investigation_regression_results, %i[regression_run_id finding_id], unique: true
  end
end
