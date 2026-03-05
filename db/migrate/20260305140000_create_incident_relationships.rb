class CreateIncidentRelationships < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_relationships, id: :uuid do |t|
      t.references :incident, type: :uuid, null: false, foreign_key: true
      t.references :related_incident, type: :uuid, null: false, foreign_key: { to_table: :incidents }
      t.string :relationship_type, null: false
      t.references :created_by, type: :uuid, null: true, foreign_key: { to_table: :workspace_memberships }

      t.timestamps
    end

    add_index :incident_relationships, [ :incident_id, :related_incident_id, :relationship_type ],
              unique: true, name: "idx_incident_relationships_unique_pair"
    add_index :incident_relationships, :relationship_type

    reversible do |dir|
      dir.up do
        execute <<~SQL
          ALTER TABLE incident_relationships
          ADD CONSTRAINT chk_no_self_reference
          CHECK (incident_id != related_incident_id)
        SQL
      end
    end
  end
end
