class AddScopedToToPolicies < ActiveRecord::Migration[8.1]
  def change
    add_column :policies, :scoped_to_type, :string
    add_column :policies, :scoped_to_id, :uuid
    add_index :policies, [ :scoped_to_type, :scoped_to_id ]

    remove_index :policies, [ :workspace_id, :domain, :name ], unique: true
    add_index :policies, [ :workspace_id, :domain, :scoped_to_type, :scoped_to_id, :name ],
              unique: true, nulls_not_distinct: true, name: "index_policies_on_scope_and_name"
  end
end
