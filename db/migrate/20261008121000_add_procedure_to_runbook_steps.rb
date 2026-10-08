class AddProcedureToRunbookSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :runbook_steps, :tool, :string
    add_column :runbook_steps, :arguments, :jsonb, null: false, default: {}
  end
end
