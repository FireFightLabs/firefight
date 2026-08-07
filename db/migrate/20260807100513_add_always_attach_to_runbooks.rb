class AddAlwaysAttachToRunbooks < ActiveRecord::Migration[8.1]
  def up
    add_column :runbooks, :always_attach, :boolean, null: false, default: false

    # A runbook with no conditions used to attach to everything by accident.
    # Existing ones keep doing that, now because someone can see they do.
    execute <<~SQL
      UPDATE runbooks SET always_attach = TRUE
      WHERE id NOT IN (
        SELECT conditionable_id FROM incident_conditions WHERE conditionable_type = 'Runbook'
      )
    SQL
  end

  def down
    remove_column :runbooks, :always_attach
  end
end
