# A polymorphic column cannot carry a foreign key. Missed when declared_by became
# polymorphic, which failed every write by a non-person.
class DropDeclaredByForeignKeys < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :incidents, column: :declared_by_id
    remove_foreign_key :incident_updates, column: :declared_by_id
  end

  def down
    add_foreign_key :incidents, :workspace_memberships, column: :declared_by_id
    add_foreign_key :incident_updates, :workspace_memberships, column: :declared_by_id
  end
end
