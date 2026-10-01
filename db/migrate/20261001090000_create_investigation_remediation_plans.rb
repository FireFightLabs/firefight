class CreateInvestigationRemediationPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :investigation_remediation_plans, id: :uuid do |t|
      t.references :finding, type: :uuid, null: false, foreign_key: { to_table: :investigation_findings, on_delete: :cascade }, index: { unique: true }
      t.text :summary, null: false
      t.text :verify
      t.string :status, null: false, default: "proposed"
      t.references :approved_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :approved_at
      t.timestamps
    end

    create_table :investigation_remediation_steps, id: :uuid do |t|
      t.references :plan, type: :uuid, null: false, foreign_key: { to_table: :investigation_remediation_plans, on_delete: :cascade }, index: false
      t.integer :position, null: false
      t.string :kind, null: false
      t.text :description, null: false
      t.string :repository
      t.string :tool_name
      t.string :action_key
      t.jsonb :arguments, default: {}, null: false
      t.text :missing
      t.text :undo
      t.integer :depends_on, array: true, default: [], null: false
      t.string :status, null: false, default: "proposed"
      t.timestamps
    end
    add_index :investigation_remediation_steps, %i[plan_id position], unique: true

    # The fix lives in the plan now. Nothing ever wrote these.
    remove_column :investigation_findings, :remediation_type, :string
    remove_column :investigation_findings, :proposed_solution, :jsonb, default: {}, null: false
  end
end
