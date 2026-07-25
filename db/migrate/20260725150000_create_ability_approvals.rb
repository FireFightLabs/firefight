class CreateAbilityApprovals < ActiveRecord::Migration[8.1]
  def change
    create_table :ability_approvals, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :workspace_id, null: false
      t.string :principal_type, null: false
      t.uuid :principal_id, null: false
      t.string :principal_label, null: false
      t.string :action_key, null: false
      t.string :request_digest, null: false
      t.jsonb :scope, default: {}, null: false
      t.jsonb :params, default: {}, null: false
      t.string :required_role, null: false
      t.string :status, default: "pending", null: false
      t.uuid :approver_id
      t.datetime :resolved_at
      t.datetime :consumed_at
      t.uuid :incident_id
      t.string :slack_channel_id
      t.string :slack_message_ts

      t.timestamps
    end

    add_index :ability_approvals, [ :workspace_id, :status, :created_at ]
    add_index :ability_approvals, [ :principal_type, :principal_id ]
    add_foreign_key :ability_approvals, :workspaces
    add_foreign_key :ability_approvals, :workspace_memberships, column: :approver_id

    add_column :ability_invocations, :approval_id, :uuid
  end
end
