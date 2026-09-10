class EnforceSingleDefaultSeverity < ActiveRecord::Migration[8.1]
  # Only a model validation guarded one default per workspace, so a raw write could produce two.
  def up
    execute <<~SQL
      UPDATE incident_severities
      SET is_default = false
      WHERE id IN (
        SELECT id FROM (
          SELECT id,
                 ROW_NUMBER() OVER (
                   PARTITION BY workspace_id ORDER BY position, created_at
                 ) AS rn
          FROM incident_severities
          WHERE is_default
        ) ranked
        WHERE rn > 1
      )
    SQL

    add_index :incident_severities, :workspace_id,
      unique: true,
      where: "is_default",
      name: "index_incident_severities_on_single_default_per_workspace"
  end

  def down
    remove_index :incident_severities, name: "index_incident_severities_on_single_default_per_workspace"
  end
end
