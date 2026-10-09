class AddPushWindowToCodeAgentSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :code_agent_sessions, :push_token_digest, :string
    add_column :code_agent_sessions, :push_open_until, :datetime
    add_index :code_agent_sessions, :push_token_digest, unique: true, where: "push_token_digest IS NOT NULL"
  end
end
