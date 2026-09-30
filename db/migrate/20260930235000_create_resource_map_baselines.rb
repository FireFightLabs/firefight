class CreateResourceMapBaselines < ActiveRecord::Migration[8.1]
  def change
    create_table :resource_map_baselines, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :resource, type: :uuid, null: false, foreign_key: { to_table: :resource_map_resources, on_delete: :cascade }, index: false
      t.string :metric, null: false
      t.string :label, null: false
      t.string :unit
      t.float :typical, null: false
      t.float :high, null: false
      t.float :peak, null: false
      t.integer :points, null: false
      t.datetime :window_from, null: false
      t.datetime :window_to, null: false
      t.timestamps
    end
    add_index :resource_map_baselines, %i[resource_id metric], unique: true
    add_index :resource_map_baselines, :workspace_id
    add_column :integration_environments, :baseline_error, :string
  end
end
