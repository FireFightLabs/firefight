class NormalizeOptionDescriptions < ActiveRecord::Migration[8.1]
  # Brings descriptions written before NormalizedDescription in line, so old and
  # new rows read the same in Slack, the dashboard and the API. Mirrors the
  # concern: capitalize a first word that is entirely lowercase, then terminate
  # the sentence.
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

  # A no-op rather than a raise: the pre-normalization text is not recoverable,
  # and normalized descriptions are valid input for the old code too.
  def down
  end
end
