class SeedIncidentFormsForExistingWorkspaces < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    Workspace.find_each do |workspace|
      workspace.setup_incident_forms!
    end
  end

  def down
    # Seeded forms are kept on rollback.
  end
end
