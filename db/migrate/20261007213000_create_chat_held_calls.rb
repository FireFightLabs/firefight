class CreateChatHeldCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :ability_approvals, :held_for_run, :boolean, default: false, null: false
    add_column :ability_approvals, :run_expires_at, :datetime

    create_table :chat_held_calls, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: true, index: false
      t.references :approval, type: :uuid, null: false, foreign_key: { to_table: :ability_approvals }, index: { unique: true }
      t.string :tool_call_id
      t.string :tool_name, null: false
      t.string :target
      t.string :status, null: false, default: "waiting"
      t.text :checked_state
      t.string :state_change
      t.datetime :state_checked_at
      t.references :decided_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :decided_at
      t.text :result
      t.uuid :invocation_id
      t.datetime :told_at
      t.string :message_channel_id
      t.string :message_id
      t.timestamps
      t.index [ :chat_id, :status ]
    end

    add_column :investigation_remediation_steps, :checked_state, :text
    add_column :investigation_remediation_steps, :state_change, :string
    add_column :investigation_remediation_steps, :state_checked_at, :datetime
  end
end
