# A call to Slack (or another platform) that failed, kept so an operator can see what did not reach people. Logs alone
# are not searchable by incident, and they do not survive a redeploy.
class CreatePlatformCallFailures < ActiveRecord::Migration[8.1]
  def change
    create_table :platform_call_failures, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :platform, null: false
      t.string :operation, null: false
      t.string :error_class, null: false
      t.text :message
      t.string :channel_id
      t.datetime :created_at, null: false
    end
    add_index :platform_call_failures, [ :workspace_id, :channel_id, :created_at ]
    add_index :platform_call_failures, :created_at
  end
end
