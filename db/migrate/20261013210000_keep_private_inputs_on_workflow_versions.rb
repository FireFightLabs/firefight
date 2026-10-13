# Private input values move from the workflow to each version, so a draft's change waits for publishing. The encrypted
# text is copied as it is, which decrypts the same on any column.
class KeepPrivateInputsOnWorkflowVersions < ActiveRecord::Migration[8.1]
  def up
    add_column :workflow_versions, :private_inputs, :text
    execute <<~SQL.squish
      UPDATE workflow_versions SET private_inputs = workflows.private_inputs
      FROM workflows
      WHERE workflow_versions.workflow_id = workflows.id AND workflows.private_inputs IS NOT NULL
        AND workflow_versions.status IN ('draft', 'live')
    SQL
    remove_column :workflows, :private_inputs
  end

  def down
    add_column :workflows, :private_inputs, :text
    execute <<~SQL.squish
      UPDATE workflows SET private_inputs = workflow_versions.private_inputs
      FROM workflow_versions
      WHERE workflow_versions.id = workflows.live_version_id
    SQL
    remove_column :workflow_versions, :private_inputs
  end
end
