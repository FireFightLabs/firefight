class EnforceSingleDefaultStatusAndType < ActiveRecord::Migration[8.1]
  TABLES = %w[incident_statuses incident_types].freeze

  # Same invariant severities just got: only a model validation stood between a
  # workspace and two defaults, so any update_all could produce them.
  def up
    TABLES.each do |table|
      execute <<~SQL
        UPDATE #{table}
        SET is_default = false
        WHERE id IN (
          SELECT id FROM (
            SELECT id,
                   ROW_NUMBER() OVER (
                     PARTITION BY workspace_id ORDER BY position, created_at
                   ) AS rn
            FROM #{table}
            WHERE is_default
          ) ranked
          WHERE rn > 1
        )
      SQL

      add_index table, :workspace_id,
        unique: true,
        where: "is_default",
        name: "index_#{table}_on_single_default_per_workspace"
    end
  end

  def down
    TABLES.each do |table|
      remove_index table, name: "index_#{table}_on_single_default_per_workspace"
    end
  end
end
