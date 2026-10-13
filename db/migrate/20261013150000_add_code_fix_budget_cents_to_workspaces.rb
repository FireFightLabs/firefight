class AddCodeFixBudgetCentsToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :code_fix_budget_cents, :integer, null: false, default: 200
  end
end
