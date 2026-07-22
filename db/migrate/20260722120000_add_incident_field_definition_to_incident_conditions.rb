class AddIncidentFieldDefinitionToIncidentConditions < ActiveRecord::Migration[8.1]
  def change
    add_reference :incident_conditions, :incident_field_definition, type: :uuid, null: true,
                  foreign_key: true
  end
end
