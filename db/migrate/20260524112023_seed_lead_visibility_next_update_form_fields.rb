class SeedLeadVisibilityNextUpdateFormFields < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Adds the new system fields to existing default forms. Idempotent, only missing rows are inserted.
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
    # Rows are kept so the form editor does not lose them on rollback.
  end
end
