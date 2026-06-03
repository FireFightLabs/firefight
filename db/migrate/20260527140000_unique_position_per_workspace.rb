class UniquePositionPerWorkspace < ActiveRecord::Migration[8.1]
  TABLES = %i[
    incident_severities
    incident_statuses
    incident_roles
    incident_types
  ].freeze

  def up
    TABLES.each do |table|
      # Renumber any per-workspace duplicates (legacy data from races) so
      # the unique index can be created. Order existing rows by id and
      # assign 1..N within each workspace.
      execute(<<~SQL)
        UPDATE #{table} AS t
        SET position = ranked.new_position
        FROM (
          SELECT id, ROW_NUMBER() OVER (PARTITION BY workspace_id ORDER BY position, id) AS new_position
          FROM #{table}
        ) AS ranked
        WHERE t.id = ranked.id AND t.position <> ranked.new_position;
      SQL

      index_name = "index_#{table}_on_workspace_id_and_position"
      remove_index table, name: index_name, if_exists: true
      add_index table, [ :workspace_id, :position ], unique: true, name: index_name
    end
  end

  def down
    TABLES.each do |table|
      index_name = "index_#{table}_on_workspace_id_and_position"
      remove_index table, name: index_name, if_exists: true
      add_index table, [ :workspace_id, :position ], name: index_name
    end
  end
end
