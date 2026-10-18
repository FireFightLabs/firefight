# A scheduled check runs in its owner's name, so what it reads is bounded by them. One whose owner left is paused until
# an admin gives it a new one, and admins are told once.
class AddOwnerToInvestigationChecks < ActiveRecord::Migration[8.1]
  def change
    add_reference :investigation_checks, :owner, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }, index: true
    add_column :investigation_checks, :paused_at, :datetime
    add_column :investigation_checks, :paused_owner_name, :string
    add_column :investigation_checks, :owner_gone_told_at, :datetime
  end
end
