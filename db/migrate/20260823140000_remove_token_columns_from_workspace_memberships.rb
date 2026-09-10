# A second copy of the bot token per installer that nothing read.
class RemoveTokenColumnsFromWorkspaceMemberships < ActiveRecord::Migration[8.1]
  def change
    remove_column :workspace_memberships, :access_token, :text
    remove_column :workspace_memberships, :refresh_token, :text
    remove_column :workspace_memberships, :token_expires_at, :datetime
  end
end
