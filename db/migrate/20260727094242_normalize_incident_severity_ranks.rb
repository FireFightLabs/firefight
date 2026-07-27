class NormalizeIncidentSeverityRanks < ActiveRecord::Migration[8.1]
  # rank used to be typed in by hand and could disagree with the order the
  # settings screen showed, so a severity could sit last while ranking highest.
  # Position is now the source of truth and rank is derived from it; this brings
  # existing rows in line so ordering by rank and by position agree everywhere.
  def up
    execute <<~SQL
      UPDATE incident_severities
      SET rank = derived.new_rank
      FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY workspace_id ORDER BY position DESC, created_at DESC
               ) AS new_rank
        FROM incident_severities
      ) AS derived
      WHERE incident_severities.id = derived.id
        AND incident_severities.rank IS DISTINCT FROM derived.new_rank
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
