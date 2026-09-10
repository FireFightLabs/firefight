class NormalizeIncidentSeverityRanks < ActiveRecord::Migration[8.1]
  # Rank was typed by hand and could disagree with position. Position is now the source
  # of truth, this derives rank from it for existing rows.
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

  # Not a raise, the hand-entered ranks are unrecoverable and normalized ranks are valid for the old code.
  def down
  end
end
