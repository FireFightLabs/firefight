# A page raised in an on-call tool for an incident, by Halon or a person, or one an alert from that tool brought in.
# Each is kept in step both ways, so acknowledging or resolving on either side reaches the other.
class CreateIncidentPages < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_pages, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :incident, type: :uuid, null: false, foreign_key: true
      t.references :integration, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :alert_source, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :origin, null: false
      t.string :state, null: false
      t.string :external_id
      t.string :reference
      t.string :title
      t.string :url
      t.string :target
      t.references :paged_member, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.string :paged_email
      t.text :details
      t.string :requested_by_type
      t.uuid :requested_by_id
      t.text :sync_note
      t.datetime :acknowledged_at
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :incident_pages, [ :workspace_id, :external_id ], unique: true, where: "external_id IS NOT NULL"

    add_column :investigation_findings, :page_email, :string
    add_column :investigation_findings, :page_target, :string
    add_reference :investigation_findings, :page_integration, type: :uuid, foreign_key: { to_table: :integrations, on_delete: :nullify }
  end
end
