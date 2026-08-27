class CreateIncidentRoleAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_role_assignments, id: :uuid do |t|
      t.uuid :incident_id, null: false
      t.uuid :incident_role_id, null: false
      t.uuid :workspace_membership_id, null: false

      t.datetime :assigned_at, null: false
      t.uuid :assigned_by_id # Who made the assignment (optional for auto-assignments)

      t.timestamps

      t.index :incident_id
      t.index [ :incident_id, :incident_role_id ], unique: true
      t.index :workspace_membership_id
      t.index :incident_role_id
    end

    # Foreign key constraints
    add_foreign_key :incident_role_assignments, :incidents
    add_foreign_key :incident_role_assignments, :incident_roles
    add_foreign_key :incident_role_assignments, :workspace_memberships
    add_foreign_key :incident_role_assignments, :workspace_memberships, column: :assigned_by_id
  end
end
