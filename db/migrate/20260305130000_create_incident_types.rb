class CreateIncidentTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_types, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :color
      t.integer :position, null: false
      t.boolean :is_default, default: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :incident_types, [ :workspace_id, :slug ], unique: true
    add_index :incident_types, [ :workspace_id, :position ]
    add_index :incident_types, :deleted_at

    add_reference :incidents, :incident_type, type: :uuid, null: true, foreign_key: true
    add_reference :incident_updates, :incident_type, type: :uuid, null: true, foreign_key: true
  end
end
