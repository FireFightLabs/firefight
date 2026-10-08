class AddPullRequestFollowingToCodeAgentSessions < ActiveRecord::Migration[8.1]
  def change
    change_table :code_agent_sessions, bulk: true do |t|
      t.uuid :integration_environment_id
      t.string :git_branch
      t.integer :pull_request_number
      t.string :pull_request_url
      t.string :pull_request_base
      t.string :pull_request_branch
      t.string :pull_request_state
      t.datetime :pull_request_checked_at
      t.datetime :pull_request_check_claimed_at
      t.datetime :pull_request_ended_at
    end
    add_index :code_agent_sessions, [ :workspace_id, :repository, :pull_request_number ],
              name: "index_code_agent_sessions_on_pull_request", where: "pull_request_number IS NOT NULL"
    add_index :code_agent_sessions, :integration_environment_id, where: "pull_request_state = 'open'",
              name: "index_code_agent_sessions_following"

    create_table :code_agent_session_notices, id: :uuid do |t|
      t.uuid :session_id, null: false
      t.uuid :workspace_id, null: false
      t.string :fingerprint, null: false
      t.jsonb :problems, null: false, default: []
      t.string :head_sha
      t.string :base
      t.string :status, null: false
      t.uuid :fix_by_id
      t.uuid :conversation_id
      t.datetime :fix_at
      t.string :message_channel_id
      t.string :message_id
      t.datetime :told_at
      t.timestamps
      t.index [ :session_id, :fingerprint ], unique: true
      t.index :workspace_id
      t.index :conversation_id
    end
    add_foreign_key :code_agent_session_notices, :code_agent_sessions, column: :session_id, on_delete: :cascade
    add_foreign_key :code_agent_session_notices, :workspaces, on_delete: :cascade
  end
end
