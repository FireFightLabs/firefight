class AddUndoToRemediationPlans < ActiveRecord::Migration[8.1]
  # A finding keeps one fix, and an applied fix at most one undo, which is a plan of its own on the same finding.
  def up
    remove_index :investigation_remediation_plans, :finding_id, unique: true
    add_reference :investigation_remediation_plans, :undoes, type: :uuid,
                  foreign_key: { to_table: :investigation_remediation_plans, on_delete: :cascade }, index: { unique: true }
    add_index :investigation_remediation_plans, :finding_id, unique: true, where: "undoes_id IS NULL", name: "index_remediation_plans_one_fix_per_finding"
    add_index :investigation_remediation_plans, :finding_id, name: "index_investigation_remediation_plans_on_finding_id"
    add_column :investigation_remediation_plans, :undo_requested_at, :datetime
    add_reference :investigation_remediation_plans, :undo_requested_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
    add_column :investigation_remediation_plans, :undo_error, :text
  end

  # Going back leaves one plan per finding, so the undos go first.
  def down
    execute "DELETE FROM investigation_remediation_plans WHERE undoes_id IS NOT NULL"
    remove_column :investigation_remediation_plans, :undo_error
    remove_reference :investigation_remediation_plans, :undo_requested_by, foreign_key: { to_table: :workspace_memberships }
    remove_column :investigation_remediation_plans, :undo_requested_at
    remove_index :investigation_remediation_plans, name: "index_investigation_remediation_plans_on_finding_id"
    remove_index :investigation_remediation_plans, name: "index_remediation_plans_one_fix_per_finding"
    remove_reference :investigation_remediation_plans, :undoes, foreign_key: { to_table: :investigation_remediation_plans }
    add_index :investigation_remediation_plans, :finding_id, unique: true
  end
end
