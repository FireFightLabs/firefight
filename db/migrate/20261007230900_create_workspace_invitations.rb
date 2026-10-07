class CreateWorkspaceInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :workspace_invitations, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :email, null: false
      t.references :invited_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.references :membership, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :last_sent_at, null: false
      t.datetime :accepted_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :workspace_invitations, [ :workspace_id, :email ], unique: true,
              where: "accepted_at IS NULL AND revoked_at IS NULL", name: "index_workspace_invitations_pending_by_email"

    add_reference :login_tokens, :workspace_invitation, type: :uuid, foreign_key: { on_delete: :cascade }
  end
end
