class RemoveAcceptIncidentForms < ActiveRecord::Migration[8.1]
  # Nothing ever opened this form. Accepting a triaged incident is a one-click
  # button, not a modal, so its rows configured a surface no responder saw.
  # Left behind they would fail the lifecycle_event inclusion validation on the
  # next save of an unrelated attribute.
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
