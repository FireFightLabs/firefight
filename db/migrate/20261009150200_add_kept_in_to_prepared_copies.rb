# A prepared copy is kept either as an archive in the app's storage or by a sandbox provider that keeps a box's disk
# itself, named by kept_ref, with the commit it was prepared at. Each place keeps its own copy of a key.
class AddKeptInToPreparedCopies < ActiveRecord::Migration[8.1]
  def change
    change_table :prepared_copies, bulk: true do |t|
      t.string :kept_in, null: false, default: "archive"
      t.string :kept_ref
      t.string :commit
    end
    remove_index :prepared_copies, name: "index_prepared_copies_on_workspace_repository_key"
    add_index :prepared_copies, [ :workspace_id, :repository, :install_key, :kept_in ], unique: true, name: "index_prepared_copies_on_workspace_repository_key"
  end
end
