class RemoveAcceptIncidentForms < ActiveRecord::Migration[8.1]
  # Nothing opened this form, accepting is a button. Left behind, the rows would fail
  # the lifecycle_event validation on the next save.
  def up
    execute(<<~SQL)
      DELETE FROM incident_form_fields
      WHERE incident_form_id IN (SELECT id FROM incident_forms WHERE slug = 'accept')
    SQL
    execute("DELETE FROM incident_forms WHERE slug = 'accept'")
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
