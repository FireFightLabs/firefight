# One row per workspace: welcome message id, dialog dismissal, completion.
# Kept off the workspace row.
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
