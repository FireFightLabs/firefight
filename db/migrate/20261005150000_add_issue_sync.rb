class AddIssueSync < ActiveRecord::Migration[8.1]
  def change
    change_table :workspaces, bulk: true do |t|
      t.string :issue_tracker
      t.string :issue_creation, null: false, default: "never"
      t.jsonb :issue_tracker_target, null: false, default: {}
      t.string :issue_webhook_token
      t.text :issue_webhook_secret
    end
    add_index :workspaces, :issue_webhook_token, unique: true

    change_table :incident_actions, bulk: true do |t|
      t.references :issue_integration, type: :uuid, foreign_key: { to_table: :integrations, on_delete: :nullify }, index: true
      t.string :issue_sync_state
      t.text :issue_sync_note
      t.uuid :issue_approval_id
      t.datetime :issue_status_synced_at
      t.datetime :issue_assignee_synced_at
      t.datetime :issue_title_synced_at
    end
    add_index :incident_actions, [ :issue_integration_id, :external_key ], where: "external_key IS NOT NULL AND deleted_at IS NULL",
                                                                            name: "index_incident_actions_on_issue_key"
  end
end
