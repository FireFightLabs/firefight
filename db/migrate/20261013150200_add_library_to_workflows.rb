class AddLibraryToWorkflows < ActiveRecord::Migration[8.1]
  def change
    change_table :workflows, bulk: true do |t|
      t.string :library_key
      t.integer :library_version
      t.jsonb :library_base
      t.boolean :follows_library, null: false, default: false
      t.integer :library_dismissed_version
      t.index [ :library_key, :follows_library ]
    end
  end
end
