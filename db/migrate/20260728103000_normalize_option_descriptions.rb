class NormalizeOptionDescriptions < ActiveRecord::Migration[8.1]
  # Old descriptions are normalized the way NormalizedDescription does on save, so old
  # and new rows read the same.
  TABLES = %w[
    incident_severities
    incident_statuses
    incident_types
    incident_roles
    incident_field_definitions
  ].freeze

  def up
    TABLES.each do |table|
      execute <<~SQL
        UPDATE #{table} AS t
        SET description = c.value || CASE
              WHEN right(c.value, 1) IN ('.', '!', '?') THEN ''
              ELSE '.'
            END
        FROM (
          SELECT id,
                 CASE
                   WHEN split_part(btrim(description), ' ', 1) = lower(split_part(btrim(description), ' ', 1))
                     THEN upper(left(btrim(description), 1)) || substr(btrim(description), 2)
                   ELSE btrim(description)
                 END AS value
          FROM #{table}
          WHERE description IS NOT NULL AND btrim(description) <> ''
        ) AS c
        WHERE t.id = c.id
          AND t.description IS DISTINCT FROM c.value || CASE
                WHEN right(c.value, 1) IN ('.', '!', '?') THEN ''
                ELSE '.'
              END
      SQL
    end
  end

  # Not a raise, the original text is unrecoverable and normalized text is valid for the old code.
  def down
  end
end
