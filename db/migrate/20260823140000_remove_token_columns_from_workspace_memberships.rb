# These held a second copy of the workspace's bot token per installer and
# were refreshed on their own schedule. Nothing read them: every Slack call
# uses the workspace's token.
class RemoveTokenColumnsFromWorkspaceMemberships < ActiveRecord::Migration[8.1]
  def change
    remove_column :workspace_memberships, :access_token, :text
    remove_column :workspace_memberships, :refresh_token, :text
    remove_column :workspace_memberships, :token_expires_at, :datetime
  end
end
