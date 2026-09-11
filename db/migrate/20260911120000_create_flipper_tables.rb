class CreateFlipperTables < ActiveRecord::Migration[8.1]
  def change
    create_table :flipper_features, id: :uuid do |t|
      t.string :key, null: false
      t.timestamps
    end
    add_index :flipper_features, :key, unique: true

    create_table :flipper_gates, id: :uuid do |t|
      t.string :feature_key, null: false
      t.string :key, null: false
      t.text :value
      t.timestamps
    end
    add_index :flipper_gates, [ :feature_key, :key, :value ], unique: true
  end
end
