# One row per workspace holding everything about its first run: the message
# in #incidents that tracks progress, whether the installer has seen the
# dashboard dialog, and when the loop was completed. Its own table so the
# workspace row stays about the workspace.
class CreateWorkspaceOnboardings < ActiveRecord::Migration[8.1]
  def change
    create_table :workspace_onboardings, id: :uuid do |t|
      t.uuid :workspace_id, null: false
      t.uuid :installer_id
      t.string :welcome_message_id
      t.datetime :dialog_dismissed_at
      t.datetime :completed_at
      t.timestamps

      t.index :workspace_id, unique: true
    end

    add_foreign_key :workspace_onboardings, :workspaces
    add_foreign_key :workspace_onboardings, :workspace_memberships, column: :installer_id, on_delete: :nullify
  end
end
