# Who paid for each model call. Every call before this one was paid by the deployment's own account, which is the
# operator's on an install someone runs themselves and Firefight's on its cloud, as Entitlements says per workspace.
class AddPayerToInferences < ActiveRecord::Migration[8.1]
  def up
    add_column :inferences, :paid_by, :string
    add_reference :inferences, :workspace_ai_account, type: :uuid, foreign_key: { on_delete: :nullify }
    add_column :inferences, :billed_micros, :bigint

    Workspace.reset_column_information
    Workspace.find_each do |workspace|
      payer = Entitlements.ai_account(workspace) == Entitlements::AI_ACCOUNT_OPERATOR ? "operator" : "firefight"
      execute(ActiveRecord::Base.sanitize_sql([ "UPDATE inferences SET paid_by = ? WHERE workspace_id = ? AND paid_by IS NULL", payer, workspace.id ]))
    end
    execute("UPDATE inferences SET paid_by = 'firefight' WHERE paid_by IS NULL")
    change_column_null :inferences, :paid_by, false
    add_index :inferences, [ :workspace_id, :paid_by, :created_at ]
  end

  def down
    remove_index :inferences, [ :workspace_id, :paid_by, :created_at ]
    remove_reference :inferences, :workspace_ai_account, foreign_key: true
    remove_column :inferences, :paid_by
    remove_column :inferences, :billed_micros
  end
end
