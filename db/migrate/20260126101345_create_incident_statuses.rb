class CreateIncidentStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_statuses, id: :uuid do |t|
      t.uuid :workspace_id, null: false

      t.string :name, null: false
      t.string :slug, null: false
      t.text :description

      t.string :category, null: false # "live" or "closed"

      t.integer :position, null: false, default: 0
      t.boolean :is_default, default: false

      t.string :color

      t.timestamps
      t.datetime :deleted_at

      t.index :workspace_id
      t.index :deleted_at
      t.index [ :workspace_id, :slug ], unique: true
      t.index [ :workspace_id, :position ]
      t.index [ :workspace_id, :category ]
      t.index [ :workspace_id, :is_default ]
    end


    add_foreign_key :incident_statuses, :workspaces
  end
end
