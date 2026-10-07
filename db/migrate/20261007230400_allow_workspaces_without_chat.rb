# A workspace can start before its team connects Slack, so the platform columns are filled when it connects.
class AllowWorkspacesWithoutChat < ActiveRecord::Migration[8.1]
  def change
    change_column_null :workspaces, :platform, true
    change_column_default :workspaces, :platform, from: "slack", to: nil
    change_column_null :workspaces, :platform_id, true
    change_column_null :workspaces, :installed_at, true
    add_reference :workspaces, :created_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
  end
end
