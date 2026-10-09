# Moves each workspace's issue tracker webhook to the environment row its chosen tracker connection is called through
# (Integration#resolve_environment with no environment), then drops it from workspaces. A workspace whose tracker has no
# such row loses its secret, so each one is named in the output for an operator to ask its admin to save it again.
class MoveIssueWebhookOffWorkspaces < ActiveRecord::Migration[8.1]
  COLUMNS = %w[issue_webhook_secret issue_webhook_id issue_webhook_expires_at issue_webhook_error].freeze

  class Workspace < ActiveRecord::Base
    self.table_name = "workspaces"
    encrypts :issue_webhook_secret
  end

  class Integration < ActiveRecord::Base
    self.table_name = "integrations"
  end

  class Environment < ActiveRecord::Base
    self.table_name = "integration_environments"
    encrypts :issue_webhook_secret
  end

  def up
    Workspace.reset_column_information
    Workspace.where.not(issue_tracker: nil).find_each do |workspace|
      values = workspace.attributes.slice(*COLUMNS)
      next if values.values.all?(&:blank?)

      row = row_for(workspace)
      if row
        row.update!(values)
      else
        say "No tracker connection environment to copy the issue webhook to for workspace #{workspace.id} (#{workspace.name})"
      end
    end
    change_table(:workspaces, bulk: true) { |t| t.remove(*COLUMNS) }
  end

  def down
    change_table :workspaces, bulk: true do |t|
      t.text :issue_webhook_secret
      t.string :issue_webhook_id
      t.datetime :issue_webhook_expires_at
      t.text :issue_webhook_error
    end
    Workspace.reset_column_information
    Workspace.where.not(issue_tracker: nil).find_each do |workspace|
      row = row_for(workspace)
      workspace.update!(row.attributes.slice(*COLUMNS)) if row
    end
  end

  private

  def row_for(workspace)
    integration = Integration.where(workspace_id: workspace.id, slug: workspace.issue_tracker).order(Arel.sql("deleted_at IS NOT NULL"), :created_at).first
    return unless integration

    rows = Environment.where(integration_id: integration.id, enabled: true)
    rows.find_by(catalog_entry_id: nil) || rows.limit(2).to_a.then { |found| found.one? ? found.first : nil }
  end
end
