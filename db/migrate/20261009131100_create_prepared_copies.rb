class CreatePreparedCopies < ActiveRecord::Migration[8.1]
  def change
    create_table :prepared_copies, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.string :repository, null: false
      t.string :install_key, null: false
      t.bigint :byte_size, null: false, default: 0
      t.datetime :last_used_at, null: false
      t.timestamps
    end
    add_index :prepared_copies, [ :workspace_id, :repository, :install_key ], unique: true, name: "index_prepared_copies_on_workspace_repository_key"
    add_index :prepared_copies, :last_used_at
  end
end
