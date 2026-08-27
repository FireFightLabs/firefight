class MakeDeclaredByPolymorphic < ActiveRecord::Migration[8.1]
  def up
    add_column :incidents, :declared_by_type, :string
    add_column :incident_updates, :declared_by_type, :string

    # Everything that exists was declared by a person, since an agent had no
    # way to declare until now.
    execute <<~SQL
      UPDATE incidents SET declared_by_type = 'WorkspaceMembership' WHERE declared_by_id IS NOT NULL;
      UPDATE incident_updates SET declared_by_type = 'WorkspaceMembership' WHERE declared_by_id IS NOT NULL;
    SQL

    add_index :incidents, [ :declared_by_type, :declared_by_id ]
  end

  def down
    remove_index :incidents, [ :declared_by_type, :declared_by_id ]
    remove_column :incidents, :declared_by_type
    remove_column :incident_updates, :declared_by_type
  end
end
