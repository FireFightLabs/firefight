class CreateIncidentSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_subscriptions, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :incident, type: :uuid, null: false, foreign_key: true
      t.references :workspace_membership, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end

    add_index :incident_subscriptions, [ :incident_id, :workspace_membership_id ], unique: true, name: "index_incident_subscriptions_on_incident_and_member"
  end
end
