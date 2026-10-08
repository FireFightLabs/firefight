# The blue that marked work in progress is gone from the palette. A row still on that exact seeded colour moves to its
# new default: statuses to the muted lime of work in progress, incident and catalogue types to the palette's yellow.
# A colour someone picked is never touched.
class MoveDefaultBlueToPalette < ActiveRecord::Migration[8.1]
  OLD = "#70D5ED".freeze
  # table, new colour
  CHANGES = [
    [ :incident_statuses, "#B7CF9A" ],
    [ :incident_types, "#EFD369" ],
    [ :catalog_types, "#EFD369" ]
  ].freeze

  def up
    CHANGES.each { |table, color| execute("UPDATE #{quote_table_name(table)} SET color = #{quote(color)} WHERE upper(color) = #{quote(OLD)}") }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
