# An agent that worked an incident should be able to write it up, and the
# record should say the agent did. Everything that exists was written by a
# person, since nothing else could until now.
class MakePostmortemAuthorPolymorphic < ActiveRecord::Migration[8.1]
  def up
    add_column :postmortems, :generated_by_type, :string
    execute "UPDATE postmortems SET generated_by_type = 'WorkspaceMembership'"
    change_column_null :postmortems, :generated_by_type, false
    remove_foreign_key :postmortems, column: :generated_by_id
    add_index :postmortems, [ :generated_by_type, :generated_by_id ]
  end

  def down
    remove_index :postmortems, [ :generated_by_type, :generated_by_id ]
    add_foreign_key :postmortems, :workspace_memberships, column: :generated_by_id
    remove_column :postmortems, :generated_by_type
  end
end
