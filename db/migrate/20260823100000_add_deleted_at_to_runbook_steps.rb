class AddDeletedAtToRunbookSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :runbook_steps, :deleted_at, :datetime
    add_index :runbook_steps, [ :runbook_id, :deleted_at ]
  end
end
