class BackfillSlackUserIdentities < ActiveRecord::Migration[8.1]
  # Every Slack account that already reaches a workspace keeps reaching the same user, matched by its Slack id before
  # its email, so nobody already signing in with Slack is asked to verify an email first. Safe to run again.
  def up
    execute <<~SQL
      INSERT INTO user_identities (id, user_id, provider, uid, email, email_verified, created_at, updated_at)
      SELECT DISTINCT ON (workspaces.platform_id, workspace_memberships.platform_user_id)
        gen_random_uuid(), users.id, 'slack', workspaces.platform_id || '/' || workspace_memberships.platform_user_id,
        users.email, false, now(), now()
      FROM workspace_memberships
      JOIN workspaces ON workspaces.id = workspace_memberships.workspace_id
      JOIN users ON users.id = workspace_memberships.user_id
      WHERE workspaces.platform = 'slack'
      ORDER BY workspaces.platform_id, workspace_memberships.platform_user_id, workspace_memberships.created_at
      ON CONFLICT (provider, uid) DO NOTHING
    SQL
  end

  def down
    execute "DELETE FROM user_identities WHERE provider = 'slack' AND last_used_at IS NULL"
  end
end
