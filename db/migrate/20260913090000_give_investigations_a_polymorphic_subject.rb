# Polymorphic subject, done before the planner is written against incident_id.
class GiveInvestigationsAPolymorphicSubject < ActiveRecord::Migration[8.1]
  def up
    add_column :investigations, :subject_type, :string
    add_column :investigations, :subject_id, :uuid

    execute <<~SQL.squish
      UPDATE investigations SET subject_type = 'Incident', subject_id = incident_id
    SQL

    change_column_null :investigations, :subject_type, false
    change_column_null :investigations, :subject_id, false

    remove_index :investigations, name: "index_investigations_on_live_incident"
    remove_index :investigations, name: "index_investigations_on_incident_id"
    remove_column :investigations, :incident_id

    add_index :investigations, [ :subject_type, :subject_id ], name: "index_investigations_on_subject"
    # One live run per subject, so a second request is refused.
    add_index :investigations, [ :subject_type, :subject_id ],
              unique: true, name: "index_investigations_on_live_subject",
              where: "status IN ('pending', 'running')"
  end

  def down
    add_column :investigations, :incident_id, :uuid
    execute <<~SQL.squish
      UPDATE investigations SET incident_id = subject_id WHERE subject_type = 'Incident'
    SQL
    execute "DELETE FROM investigations WHERE incident_id IS NULL"
    change_column_null :investigations, :incident_id, false

    remove_index :investigations, name: "index_investigations_on_live_subject"
    remove_index :investigations, name: "index_investigations_on_subject"
    remove_column :investigations, :subject_type
    remove_column :investigations, :subject_id

    add_index :investigations, :incident_id, name: "index_investigations_on_incident_id"
    add_index :investigations, :incident_id,
              unique: true, name: "index_investigations_on_live_incident",
              where: "status IN ('pending', 'running')"
  end
end
