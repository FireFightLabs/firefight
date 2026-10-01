class AddApplyingToRemediationPlans < ActiveRecord::Migration[8.1]
  def change
    # The answer's own message, so applying its fix can redraw it without the button.
    add_column :investigations, :answer_message_id, :string

    change_table :investigation_remediation_plans, bulk: true do |t|
      t.string :applied_from
      t.string :progress_channel_id
      t.string :progress_message_id
    end

    change_table :investigation_remediation_steps, bulk: true do |t|
      t.references :invocation, type: :uuid, foreign_key: { to_table: :ability_invocations, on_delete: :nullify }
      t.references :approval, type: :uuid, foreign_key: { to_table: :ability_approvals, on_delete: :nullify }
      t.references :done_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.text :result
      t.datetime :started_at
      t.datetime :finished_at
    end
  end
end
