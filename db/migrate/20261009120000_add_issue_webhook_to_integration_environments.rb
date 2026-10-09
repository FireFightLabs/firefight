# The issue tracker's webhook and its signing secret belong to the tracker connection's environment row, beside the
# map's own, since only IntegrationEnvironment and WorkspaceAiAccount keep secrets.
class AddIssueWebhookToIntegrationEnvironments < ActiveRecord::Migration[8.1]
  def change
    change_table :integration_environments, bulk: true do |t|
      t.text :issue_webhook_secret
      t.string :issue_webhook_id
      t.datetime :issue_webhook_expires_at
      t.text :issue_webhook_error
    end
  end
end
