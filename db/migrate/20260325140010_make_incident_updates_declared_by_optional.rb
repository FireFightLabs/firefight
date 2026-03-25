class MakeIncidentUpdatesDeclaredByOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :incident_updates, :declared_by_id, true
  end
end
