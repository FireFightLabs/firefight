class AddCancelledToRemediationPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :investigation_remediation_plans, :cancelled_at, :datetime
    add_reference :investigation_remediation_plans, :cancelled_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
  end
end
