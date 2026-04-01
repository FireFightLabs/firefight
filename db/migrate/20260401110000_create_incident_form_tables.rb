class CreateIncidentFormTables < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_field_definitions, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.string :field_type, null: false
      t.string :option_source, null: false
      t.jsonb :config, null: false, default: {}
      t.integer :position, null: false
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :incident_field_definitions, [ :workspace_id, :key ], unique: true,
      where: "deleted_at IS NULL",
      name: "index_incident_field_definitions_on_workspace_and_key_active"

    create_table :incident_forms, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :name, null: false
      t.text :description
      t.string :lifecycle_event, null: false
      t.integer :position, null: false
      t.timestamps
    end

    add_index :incident_forms, [ :workspace_id, :slug ], unique: true

    create_table :incident_form_fields, id: :uuid do |t|
      t.references :incident_form, type: :uuid, null: false, foreign_key: true
      t.string :field_source_kind, null: false
      t.string :system_field_key
      t.references :incident_field_definition, type: :uuid, null: true, foreign_key: true
      t.integer :position, null: false
      t.string :visibility_mode, null: false, default: "visible"
      t.string :required_mode, null: false, default: "optional"
      t.jsonb :config, null: false, default: {}
      t.timestamps
    end

    add_index :incident_form_fields,
      [ :incident_form_id, :field_source_kind, :system_field_key ],
      unique: true,
      where: "system_field_key IS NOT NULL",
      name: "index_incident_form_fields_on_form_and_system_field"

    add_index :incident_form_fields,
      [ :incident_form_id, :incident_field_definition_id ],
      unique: true,
      where: "incident_field_definition_id IS NOT NULL",
      name: "index_incident_form_fields_on_form_and_field_definition"
  end
end
