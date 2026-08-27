class NormalizeCustomFieldOptionsAndValues < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_field_options, id: :uuid do |t|
      t.references :incident_field_definition, type: :uuid, null: false,
        foreign_key: true, index: false
      t.string :label, null: false
      t.integer :position, null: false
      t.datetime :disabled_at
      t.timestamps
    end

    add_index :incident_field_options, [ :incident_field_definition_id, :position ],
      name: "index_incident_field_options_on_definition_and_position"
    add_index :incident_field_options, [ :incident_field_definition_id, :label ],
      unique: true, where: "disabled_at IS NULL",
      name: "index_incident_field_options_on_definition_and_label_active"

    add_reference :incident_field_definitions, :catalog_type, type: :uuid,
      foreign_key: true, index: true

    create_table :incident_field_values, id: :uuid do |t|
      t.references :incident, type: :uuid, null: false, index: false
      t.references :incident_field_definition, type: :uuid, null: false, index: true
      t.references :incident_field_option, type: :uuid, index: true
      t.references :catalog_entry, type: :uuid, index: true
      t.text :value_text
      t.decimal :value_number
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_foreign_key :incident_field_values, :incidents, on_delete: :cascade
    add_foreign_key :incident_field_values, :incident_field_definitions

    # The whole point of the table, an option or catalog entry that an incident
    # points at cannot be deleted out from under it by the database, not by a
    # check someone remembered to write.
    add_foreign_key :incident_field_values, :incident_field_options, on_delete: :restrict
    add_foreign_key :incident_field_values, :catalog_entries, on_delete: :restrict

    add_index :incident_field_values, [ :incident_id, :incident_field_definition_id ],
      name: "index_incident_field_values_on_incident_and_definition"

    add_index :incident_field_values,
      [ :incident_id, :incident_field_definition_id, :incident_field_option_id ],
      unique: true, where: "incident_field_option_id IS NOT NULL",
      name: "index_incident_field_values_unique_option"

    add_index :incident_field_values,
      [ :incident_id, :incident_field_definition_id, :catalog_entry_id ],
      unique: true, where: "catalog_entry_id IS NOT NULL",
      name: "index_incident_field_values_unique_catalog_entry"

    # Text, number, and link fields hold one value per incident. Selects are
    # excluded so multi-select can write several rows.
    add_index :incident_field_values, [ :incident_id, :incident_field_definition_id ],
      unique: true,
      where: "incident_field_option_id IS NULL AND catalog_entry_id IS NULL",
      name: "index_incident_field_values_unique_scalar"

    add_check_constraint :incident_field_values,
      "(incident_field_option_id IS NOT NULL)::int + " \
      "(catalog_entry_id IS NOT NULL)::int + " \
      "(value_text IS NOT NULL)::int + " \
      "(value_number IS NOT NULL)::int = 1",
      name: "incident_field_values_exactly_one_value"
  end
end
