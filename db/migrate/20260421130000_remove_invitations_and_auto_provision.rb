class RemoveInvitationsAndAutoProvision < ActiveRecord::Migration[8.1]
  def change
    drop_table :invitations do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :invited_by, type: :uuid, null: false, foreign_key: { to_table: :workspace_memberships }
      t.string :email, null: false
      t.datetime :expires_at, null: false
      t.datetime :redeemed_at
      t.references :redeemed_by, type: :uuid, foreign_key: { to_table: :workspace_memberships }

      t.timestamps
      t.index [ :workspace_id, :email ]
    end

    remove_column :workspaces, :allow_auto_provision, :boolean, null: false, default: false
  end
end
