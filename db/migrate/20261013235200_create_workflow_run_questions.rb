# What a workflow's Ask a person step asked, of whom, and the answer that carries the run on.
class CreateWorkflowRunQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :workflow_run_questions, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :run_step, type: :uuid, null: false, foreign_key: { to_table: :workflow_run_steps, on_delete: :cascade }
      t.uuid :engine_step_id, null: false
      t.string :delivery_key, null: false
      t.text :question, null: false
      t.text :details
      t.string :choices, array: true, null: false, default: []
      t.jsonb :fields, null: false, default: []
      t.uuid :asked_member_ids, array: true, null: false, default: []
      t.string :status, null: false, default: "open"
      t.jsonb :answer
      t.references :answered_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :answered_at
      t.datetime :due_at, null: false
      t.jsonb :notifications, null: false, default: []
      t.timestamps
    end
    add_index :workflow_run_questions, %i[workspace_id status]
  end
end
