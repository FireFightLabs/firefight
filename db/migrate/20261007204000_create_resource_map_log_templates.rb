class CreateResourceMapLogTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :resource_map_log_templates, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: true
      t.references :resource, type: :uuid, null: false, foreign_key: { to_table: :resource_map_resources, on_delete: :cascade }, index: false
      t.references :integration_environment, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :digest, null: false
      t.text :template, null: false
      t.string :level
      t.integer :lines, null: false
      t.integer :samples, null: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    add_index :resource_map_log_templates, %i[resource_id digest], unique: true
    add_column :integration_environments, :log_patterns_error, :string
  end
end
