# Moves the seeded defaults to the dashboard palette. Only a row still on its exact old
# default changes, so a colour an admin picked is never touched.
class MoveDefaultColorsToPalette < ActiveRecord::Migration[8.1]
  # table, key column, key, old colour, new colour
  CHANGES = [
    [ :incident_severities, :slug, "critical", "#D42B2B", "#F05653" ],
    [ :incident_severities, :slug, "major", "#E07A12", "#F18336" ],
    [ :incident_severities, :slug, "minor", "#3B82F6", "#EFD369" ],
    [ :incident_statuses, :slug, "triaging", "#8B5CF6", "#A98AEA" ],
    [ :incident_statuses, :slug, "investigating", "#38BDF8", "#70D5ED" ],
    [ :incident_statuses, :slug, "identified", "#14B8A6", "#70D5ED" ],
    [ :incident_statuses, :slug, "monitoring", "#22C55E", "#70D5ED" ],
    [ :incident_statuses, :slug, "resolved", "#16A34A", "#9EE464" ],
    [ :incident_statuses, :slug, "canceled", "#6B7280", "#9D9F9D" ],
    [ :incident_types, :slug, "production", "#DC143C", "#9EE464" ],
    [ :incident_types, :slug, "security", "#8B5CF6", "#70D5ED" ],
    [ :incident_types, :slug, "infrastructure", "#F59E0B", "#A98AEA" ],
    [ :incident_types, :slug, "data", "#3B82F6", "#F18336" ],
    [ :incident_types, :slug, "third_party", "#10B981", "#9D9F9D" ],
    [ :catalog_types, :system_key, "team", "#8B5CF6", "#9EE464" ],
    [ :catalog_types, :system_key, "service", "#3B82F6", "#70D5ED" ],
    [ :catalog_types, :system_key, "environment", "#10B981", "#A98AEA" ],
    [ :catalog_types, :system_key, "functionality", "#F59E0B", "#F18336" ]
  ].freeze

  def up
    CHANGES.each { |table, column, key, old_color, new_color| recolor(table, column, key, old_color, new_color) }
  end

  def down
    CHANGES.each { |table, column, key, old_color, new_color| recolor(table, column, key, new_color, old_color) }
  end

  private

  def recolor(table, column, key, from, to)
    execute <<~SQL.squish
      UPDATE #{quote_table_name(table)} SET color = #{quote(to)}
      WHERE #{quote_column_name(column)} = #{quote(key)} AND upper(color) = #{quote(from)}
    SQL
  end
end
