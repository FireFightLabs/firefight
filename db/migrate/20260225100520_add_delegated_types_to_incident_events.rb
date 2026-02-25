class AddDelegatedTypesToIncidentEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :incident_events, :eventable_type, :string
    add_column :incident_events, :eventable_id, :uuid
    add_index :incident_events, [ :eventable_type, :eventable_id ]
  end
end
