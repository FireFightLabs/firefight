class SeedLeadVisibilityNextUpdateFormFields < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Add the newly-registered system fields (lead / visibility / next_update)
  # to existing workspaces' default forms. Idempotent via `find_or_create_by!`
  # in `setup_incident_forms!`, only inserts rows that don't already exist.
  def up
    Workspace.find_each do |workspace|
      workspace.setup_incident_forms!
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn({
        event: "migration.seed_lead_visibility_next_update.skipped",
        workspace_id: workspace.id,
        error: e.message
      })
    end
  end

  def down
    # No-op: keep the seeded rows so existing workspaces don't lose visibility
    # in the form editor on rollback.
  end
end
