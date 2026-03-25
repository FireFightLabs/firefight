class AddSourceToIncidents < ActiveRecord::Migration[8.1]
  def up
    add_column :incidents, :source, :string
    add_column :incidents, :source_api_key_id, :uuid

    # Backfill existing incidents as slack-sourced
    execute "UPDATE incidents SET source = 'slack' WHERE source IS NULL"

    change_column_null :incidents, :source, false
    change_column_null :incidents, :declared_by_id, true

    add_index :incidents, :source
    add_foreign_key :incidents, :api_keys, column: :source_api_key_id
  end

  def down
    remove_foreign_key :incidents, column: :source_api_key_id
    remove_index :incidents, :source
    change_column_null :incidents, :declared_by_id, false
    remove_column :incidents, :source_api_key_id
    remove_column :incidents, :source
  end
end
