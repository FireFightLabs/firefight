# A teammate invited by email has no chat account yet. A person is still one member of a workspace, so that pair
# becomes unique.
class AllowMembershipsWithoutPlatformUser < ActiveRecord::Migration[8.1]
  def up
    duplicates = select_rows(<<~SQL)
      SELECT workspace_id::text, user_id::text, string_agg(id::text, ', ' ORDER BY created_at)
      FROM workspace_memberships
      GROUP BY workspace_id, user_id
      HAVING count(*) > 1
    SQL

    if duplicates.any?
      list = duplicates.map { |workspace_id, user_id, ids| "workspace #{workspace_id}, user #{user_id}: #{ids}" }.join("\n")
      raise ActiveRecord::MigrationError, "These people hold more than one membership in a workspace. Merge them, then run again.\n#{list}"
    end

    change_column_null :workspace_memberships, :platform_user_id, true
    add_index :workspace_memberships, [ :workspace_id, :user_id ], unique: true,
              name: "index_workspace_memberships_on_workspace_and_user"
  end

  def down
    remove_index :workspace_memberships, name: "index_workspace_memberships_on_workspace_and_user"
    change_column_null :workspace_memberships, :platform_user_id, false
  end
end
