class AddRunbookStepToIncidentActions < ActiveRecord::Migration[8.1]
  def change
    add_reference :incident_actions, :runbook_step, type: :uuid, foreign_key: true, index: false

    # Stops two responders claiming the same row at once from both winning.
    add_index :incident_actions, [ :incident_id, :runbook_step_id ],
              unique: true,
              where: "runbook_step_id IS NOT NULL AND deleted_at IS NULL",
              name: "index_incident_actions_on_incident_and_runbook_step"

    remove_column :incident_runbooks, :applied_at, :datetime
    remove_reference :incident_runbooks, :applied_by, type: :uuid, foreign_key: { to_table: :workspace_memberships }
  end
end
